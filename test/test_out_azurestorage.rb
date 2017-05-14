require 'fluent/test'
require 'fluent/test/driver/output'
require 'fluent/test/helpers'
require 'fluent/plugin/out_azurestorage'

require 'test/unit/rr'
require 'zlib'
require 'fileutils'

include Fluent::Test::Helpers

class AzureStorageOutputTest < Test::Unit::TestCase
  def setup
    require 'azure'
    Fluent::Test.setup
  end

  CONFIG = %[
    azure_storage_account test_storage_account
    azure_storage_access_key dGVzdF9zdG9yYWdlX2FjY2Vzc19rZXk=
    azure_container test_container
    path log
    utc
    buffer_type memory
  ]

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::AzureStorageOutput) do
      # for testing.
      def contents
        @emit_streams
      end

      def write(chunk)
        @emit_streams = []
        event = chunk.read
        @emit_streams << event
      end

      private

      def ensure_container
      end

    end.configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal 'test_storage_account', d.instance.azure_storage_account
    assert_equal 'dGVzdF9zdG9yYWdlX2FjY2Vzc19rZXk=', d.instance.azure_storage_access_key
    assert_equal 'test_container', d.instance.azure_container
    assert_equal 'log', d.instance.path
    assert_equal 'gz', d.instance.instance_variable_get(:@compressor).ext
    assert_equal 'application/x-gzip', d.instance.instance_variable_get(:@compressor).content_type
  end

  def test_configure_with_mime_type_json
    conf = CONFIG.clone
    conf << "\nstore_as json\n"
    d = create_driver(conf)
    assert_equal 'json', d.instance.instance_variable_get(:@compressor).ext
    assert_equal 'application/json', d.instance.instance_variable_get(:@compressor).content_type
  end

  def test_configure_with_mime_type_text
    conf = CONFIG.clone
    conf << "\nstore_as text\n"
    d = create_driver(conf)
    assert_equal 'txt', d.instance.instance_variable_get(:@compressor).ext
    assert_equal 'text/plain', d.instance.instance_variable_get(:@compressor).content_type
  end

  def test_configure_with_mime_type_lzo
    conf = CONFIG.clone
    conf << "\nstore_as lzo\n"
    d = create_driver(conf)
    # Fallback to text/plain.
    assert_equal 'txt', d.instance.instance_variable_get(:@compressor).ext
    assert_equal 'text/plain', d.instance.instance_variable_get(:@compressor).content_type
  end

  def test_path_slicing
    config = CONFIG.clone.gsub(/path\slog/, "path log/%Y/%m/%d")
    d = create_driver(config)
    path_slicer = d.instance.instance_variable_get(:@path_slicer)
    path = d.instance.instance_variable_get(:@path)
    slice = path_slicer.call(path)
    assert_equal slice, Time.now.utc.strftime("log/%Y/%m/%d")
  end

  def test_path_slicing_utc
    config = CONFIG.clone.gsub(/path\slog/, "path log/%Y/%m/%d")
    config << "\nutc\n"
    d = create_driver(config)
    path_slicer = d.instance.instance_variable_get(:@path_slicer)
    path = d.instance.instance_variable_get(:@path)
    slice = path_slicer.call(path)
    assert_equal slice, Time.now.utc.strftime("log/%Y/%m/%d")
  end

  def test_format
    d = create_driver

    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      d.feed(time, {"a"=>1})
      d.feed(time, {"a"=>2})
    end
    formatted = d.formatted

    assert_equal %[2011-01-02T13:14:15Z\ttest\t{"a":1}\n], formatted[0]
    assert_equal %[2011-01-02T13:14:15Z\ttest\t{"a":2}\n], formatted[1]
  end

  def test_format_included_tag_and_time
    config = [CONFIG, 'include_tag_key true', 'include_time_key true'].join("\n")
    d = create_driver(config)

    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      d.feed(time, {"a"=>1})
      d.feed(time, {"a"=>2})
    end
    formatted = d.formatted

    assert_equal %[2011-01-02T13:14:15Z\ttest\t{"a":1,"tag":"test","time":"2011-01-02T13:14:15Z"}\n], formatted[0]
    assert_equal %[2011-01-02T13:14:15Z\ttest\t{"a":2,"tag":"test","time":"2011-01-02T13:14:15Z"}\n], d.formatted[1]
  end

  def test_format_with_format_ltsv
    config = [CONFIG, 'format ltsv'].join("\n")
    d = create_driver(config)

    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      d.feed(time, {"a"=>1, "b"=>1})
      d.feed(time, {"a"=>2, "b"=>2})
    end
    formatted = d.formatted

    assert_equal %[a:1\tb:1\n], formatted[0]
    assert_equal %[a:2\tb:2\n], formatted[1]
  end

  def test_format_with_format_json
    config = [CONFIG, 'format json'].join("\n")
    d = create_driver(config)

    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      d.feed(time, {"a"=>1})
      d.feed(time, {"a"=>2})
    end
    formatted = d.formatted

    assert_equal %[{"a":1}\n], formatted[0]
    assert_equal %[{"a":2}\n], formatted[1]
  end

  def test_format_with_format_json_included_tag
    config = [CONFIG, 'format json', 'include_tag_key true'].join("\n")
    d = create_driver(config)

    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      d.feed(time, {"a"=>1})
      d.feed(time, {"a"=>2})
    end
    formatted = d.formatted

    assert_equal %[{"a":1,"tag":"test"}\n], formatted[0]
    assert_equal %[{"a":2,"tag":"test"}\n], formatted[1]
  end

  def test_format_with_format_json_included_time
    config = [CONFIG, 'format json', 'include_time_key true'].join("\n")
    d = create_driver(config)

    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      d.feed(time, {"a"=>1})
      d.feed(time, {"a"=>2})
    end
    formatted = d.formatted

    assert_equal %[{"a":1,"time":"2011-01-02T13:14:15Z"}\n], formatted[0]
    assert_equal %[{"a":2,"time":"2011-01-02T13:14:15Z"}\n], formatted[1]
  end

  def test_format_with_format_json_included_tag_and_time
    config = [CONFIG, 'format json', 'include_tag_key true', 'include_time_key true'].join("\n")
    d = create_driver(config)

    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      d.feed(time, {"a"=>1})
      d.feed(time, {"a"=>2})
    end
    formatted = d.formatted

    assert_equal %[{"a":1,"tag":"test","time":"2011-01-02T13:14:15Z"}\n], formatted[0]
    assert_equal %[{"a":2,"tag":"test","time":"2011-01-02T13:14:15Z"}\n], formatted[1]
  end

  def test_chunk_to_write
    d = create_driver

    time = event_time("2011-01-02 13:14:15 UTC")
    d.run(default_tag: "test") do
      d.feed(time, {"a"=>1})
      d.feed(time, {"a"=>2})
    end

    # Stubbed #write and #emit_streams returns chunk.read result.
    data = d.instance.contents

    assert_equal [%[2011-01-02T13:14:15Z\ttest\t{"a":1}\n] +
                 %[2011-01-02T13:14:15Z\ttest\t{"a":2}\n]],
                 data
  end

  CONFIG_TIME_SLICE = %[
    hostname testing.node.local
    azure_storage_account test_storage_account
    azure_storage_access_key dGVzdF9zdG9yYWdlX2FjY2Vzc19rZXk=
    azure_container test_container
    azure_object_key_format %{path}/events/ts=%{time_slice}/events_%{index}-%{hostname}.%{file_extension}
    time_slice_format %Y%m%d-%H
    path log
    utc
    buffer_type memory
    log_level debug
  ]

  def create_time_sliced_driver(conf = CONFIG_TIME_SLICE)
    d = Fluent::Test::Driver::Output.new(Fluent::Plugin::AzureStorageOutput) do
    end.configure(conf)
    d
  end

end
