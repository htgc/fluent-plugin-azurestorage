require 'test/unit/rr'
require 'zlib'
require 'fileutils'
require 'azure/storage/blob'

class AzureStorageOutputTest < Test::Unit::TestCase
  def setup
    # @blob_client = Azure::Storage::Blob::BlobService
    #                    .create(storage_account_name: "tkwugen2",
    #                            storage_access_key: "sg+uj/TzZeV147on0kvdm3bv2UOEan06iO2QjsBQ8LWK3/7dSNJwEIR2eGuFmPsnVOsqUNrKiLDsABs3gpQCKA==")

    # This token is container-wide so account-wide operations, such as create container, don't work.
    # Meaning that container needs to exist before putting files.
    @blob_client = Azure::Storage::Blob::BlobService
                       .create(storage_account_name: "tkwugen2",
                               storage_sas_token: "sr=c&sp=rw&sv=2017-07-29&st=2018-10-24T20%3A42%3A13Z&sig=RYehdIyUfcdc8wGEa9vJrnlby6u4jbm6SwLYcACsF3U%3D&se=2019-08-01T20%3A42%3A13Z")
  end

  def test_azure_storage
    container_name = "system"
    @blob_client.create_container(container_name)
    # Set the permission so the blobs are public.
    @blob_client.set_container_acl(container_name, "container")

    local_path=File.expand_path("~/curl_hue_proxy.txt")
    container_path = "curl_hue_proxy.txt"
    @blob_client.create_block_blob(container_name, container_path, local_path)
  end

end
