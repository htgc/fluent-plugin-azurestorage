require 'pathname'
require 'thread'

module UploadService
  MAX_BLOCK_SIZE = 4 * 1024 * 1024 # 4MB
  MAX_PUT_SIZE = 64 * 1024 * 1024 # 64MB
  THREAD_COUNT = 10

  def self.extended(base)
  end

  def upload(source, options = {})
    @thread_count = options[:thread_count] || THREAD_COUNT

    size = File.size(source)

    if size <= MAX_PUT_SIZE
      content = File.open(source, 'rb') { |file| file.read }
      self.create_block_blob(options[:container], options[:blob], content)
    else
      blocks = upload_blocks(source, options)
      complete_upload(blocks, options)
    end
  end

  def complete_upload(blocks, options)
    options[:blob_content_type] = options[:content_type]

    self.commit_blob_blocks(options[:container], options[:blob], blocks.map{ |block| [block[:block_id], :uncommitted] }, options)
  end

  def upload_blocks(source, options)
    pending = BlockList.new(compute_blocks(source, options))
    completed = BlockList.new
    errors = upload_in_threads(pending, completed)
    if errors.empty?
      completed.to_a.sort_by { |block| block[:block_number] }
    else
      msg = "multipart upload failed: #{errors.map(&:message).join("; ")}"
      raise BlockUploadError.new(msg, errors)
    end
  end

  def compute_blocks(source, options)
    size = File.size(source)
    offset = 0
    block_number = 1
    blocks = []
    while offset < size
      blocks << {
          container: options[:container],
          blob: options[:blob],
          block_id: block_number.to_s.rjust(5, '0'),
          block_number: block_number,
          body: FilePart.new(
              source: source,
              offset: offset,
              size: block_size(size, MAX_BLOCK_SIZE, offset)
          )
      }
      block_number += 1
      offset += MAX_BLOCK_SIZE
    end
    blocks
  end

  def upload_in_threads(pending, completed)
    threads = []
    @thread_count.times do
      thread = Thread.new do
        begin
          while block = pending.shift
            content = block[:body].read
            block[:body].close

            options = {}
            options[:content_md5] = Base64.strict_encode64(Digest::MD5.digest(content))
            options[:timeout] = 30

            content_md5 = self.create_blob_block(block[:container], block[:blob], block[:block_id], content, options)

            if content_md5 != options[:content_md5]
              raise "The block is corrupt: block = #{block[:block_id]}"
            end

            completed.push(block_id: block[:block_id], block_number: block[:block_number])
          end
          nil
        rescue => error
          # keep other threads from uploading other parts
          pending.clear!
          error
        end
      end
      thread.abort_on_exception = true
      threads << thread
    end
    threads.map(&:value).compact
  end

  def block_size(total_size, block_size, offset)
    if offset + block_size > total_size
      total_size - offset
    else
      block_size
    end
  end

  # @api private
  class BlockList

    def initialize(blocks = [])
      @blocks = blocks
      @mutex = Mutex.new
    end

    def push(block)
      @mutex.synchronize { @blocks.push(block) }
    end

    def shift
      @mutex.synchronize { @blocks.shift }
    end

    def clear!
      @mutex.synchronize { @blocks.clear }
    end

    def to_a
      @mutex.synchronize { @blocks.dup }
    end

  end

  class BlockUploadError < StandardError

    def initialize(message, errors)
      @errors = errors
      super(message)
    end

    attr_reader :errors

  end

  class FilePart

    def initialize(options = {})
      @source = options[:source]
      @first_byte = options[:offset]
      @last_byte = @first_byte + options[:size]
      @size = options[:size]
      @file = nil
    end

    # @return [String,Pathname,File,Tempfile]
    attr_reader :source

    # @return [Integer]
    attr_reader :first_byte

    # @return [Integer]
    attr_reader :last_byte

    # @return [Integer]
    attr_reader :size

    def read(bytes = nil, output_buffer = nil)
      open_file unless @file
      read_from_file(bytes, output_buffer)
    end

    def rewind
      if @file
        @file.seek(@first_byte)
        @position = @first_byte
      end
      0
    end

    def close
      @file.close if @file
    end

    private

    def open_file
      @file = File.open(@source, 'rb')
      rewind
    end

    def read_from_file(bytes, output_buffer)
      if bytes
        data = @file.read([remaining_bytes, bytes].min)
        data = nil if data == ''
      else
        data = @file.read(remaining_bytes)
      end
      @position += data ? data.bytesize : 0
      output_buffer ? output_buffer.replace(data || '') : data
    end

    def remaining_bytes
      @last_byte - @position
    end

  end
end