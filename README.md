# Azure Storage output plugin for Fluentd

[![Build Status](https://travis-ci.org/htgc/fluent-plugin-azurestorage.svg?branch=master)](https://travis-ci.org/htgc/fluent-plugin-azurestorage)

## Overview

Azure Storate output plugin buffers logs in local file and upload them to Azure Storage periodically.
This plugin is porting from [fluent-plugin-s3](https://github.com/fluent/fluent-plugin-s3) for AzureStorage.

## Installation

Install from RubyGems:
```
$ gem install fluent-plugin-azurestorage
```

## Configuration

### v0.14 style

```
<match pattern>
  type azurestorage

  azure_storage_account    <your azure storage account>
  azure_storage_access_key <your azure storage access key>
  azure_container          <your azure storage container>
  azure_storage_type       blob
  store_as                 gzip
  auto_create_container    true
  path                     logs/
  azure_object_key_format  %{path}%{time_slice}_%{index}.%{file_extension}
  time_slice_format        %Y%m%d-%H
  # if you want to use ${tag} or %Y/%m/%d/ like syntax in path / s3_object_key_format,
  # need to specify tag for ${tag} and time for %Y/%m/%d in <buffer> argument.
  <buffer tag,time>
    @type file
    path /var/log/fluent/azurestorage
    timekey 3600 # 1 hour partition
    timekey_wait 10m
    timekey_use_utc true # use utc
  </buffer>
</match>
```

For `<buffer>`, you can use any record field in `path` / `azure_object_key_format`.

```
path logs/${tag}/${foo}
<buffer tag,foo>
  # parameters...
</buffer>
```

See official article for more detail: Buffer section configurations

Note that this configuration doesn't work with fluentd v0.12.

### v0.12 style

```
<match pattern>
  type azurestorage

  azure_storage_account    <your azure storage account>
  azure_storage_access_key <your azure storage access key>
  azure_container          <your azure storage container>
  azure_storage_type       blob
  store_as                 gzip 
  auto_create_container    true
  path                     logs/
  azure_object_key_format  %{path}%{time_slice}_%{index}.%{file_extension}
  buffer_path              /var/log/fluent/azurestorage

  time_slice_format        %Y%m%d-%H
  time_slice_wait          10m
  utc
</match>
```

### azure_storage_account

Your Azure Storage Account Name. This can be got from Azure Management potal.
This parameter is required when environment variable 'AZURE_STORAGE_ACCOUNT' is not set.

### azure_storage_access_key

Your Azure Storage Access Key(Primary or Secondary). This also can be got from Azure Management potal.
This parameter is required when environment variable 'AZURE_STORAGE_ACCESS_KEY' is not set.

### azure_container (Required)

Azure Storage Container name

### auto_create_container

This plugin create container if not exist when you set 'auto_create_container' to true.

### azure_storage_type

Azure Storage type. Now supports only 'blob'(default). 'tables' and 'queues' are not implemented.

### azure_object_key_format

The format of Azure Storage object keys. You can use several built-in variables:

- %{path}
- %{time_slice}
- %{index}
- %{file_extension}

to decide keys dynamically.

%{path} is exactly the value of *path* configured in the configuration file. E.g., "logs/" in the example configuration above.
%{time_slice} is the time-slice in text that are formatted with *time_slice_format*.
%{index} is the sequential number starts from 0, increments when multiple files are uploaded to Azure Storage in the same time slice.
%{file_extention} is always "gz" for now.

The default format is "%{path}%{time_slice}_%{index}.%{file_extension}".

For instance, using the example configuration above, actual object keys on Azure Storage will be something like:

```
"logs/20130111-22_0.gz"
"logs/20130111-23_0.gz"
"logs/20130111-23_1.gz"
"logs/20130112-00_0.gz"
```

With the configuration:

```
azure_object_key_format %{path}/events/ts=%{time_slice}/events_%{index}.%{file_extension}
path log
time_slice_format %Y%m%d-%H
```

You get:

```
"log/events/ts=20130111-22/events_0.gz"
"log/events/ts=20130111-23/events_0.gz"
"log/events/ts=20130111-23/events_1.gz"
"log/events/ts=20130112-00/events_0.gz"
```

The [fluent-mixin-config-placeholders](https://github.com/tagomoris/fluent-mixin-config-placeholders) mixin is also incorporated, so additional variables such as %{hostname}, %{uuid}, etc. can be used in the azure_object_key_format. This could prove useful in preventing filename conflicts when writing from multiple servers.

```
azure_object_key_format %{path}/events/ts=%{time_slice}/events_%{index}-%{hostname}.%{file_extension}
```

### store_as

Archive format on Azure Storage. You can use following types:

- gzip (default)
- json
- text
- lzo (Need lzop command)
- lzma2 (Need xz command)

### format

Change one line format in the Azure Storage object. Supported formats are 'out_file', 'json', 'ltsv' and 'single_value'.

- out_file (default)

```
time\ttag\t{..json1..}
time\ttag\t{..json2..}
...
```

- json

```
{..json1..}
{..json2..}
...
```

At this format, "time" and "tag" are omitted.
But you can set these information to the record by setting "include_tag_key" / "tag_key" and "include_time_key" / "time_key" option.
If you set following configuration in AzureStorage output:

```
format json
include_time_key true
time_key log_time # default is time
```

then the record has log_time field.

```
{"log_time":"time string",...}
```

- ltsv

```
key1:value1\tkey2:value2
key1:value1\tkey2:value2
...
```

"ltsv" format also accepts "include_xxx" related options. See "json" section.

- single_value

Use specified value instead of entire recode. If you get '{"message":"my log"}', then contents are

```
my log1
my log2
...
```

You can change key name by "message_key" option.

### path

path prefix of the files on Azure Storage. Default is "" (no prefix).

### buffer_path (required)

path prefix of the files to buffer logs.

### time_slice_format

Format of the time used as the file name. Default is '%Y%m%d'. Use '%Y%m%d%H' to split files hourly.

### time_slice_wait

The time to wait old logs. Default is 10 minutes. Specify larger value if old logs may reache.

### utc

Use UTC instead of local time.

## License
Azure Storage output plugin is licensed according to the terms of the Apache License, Version 2.0.

The full version of this lisence can be found at http://www.apache.org/licenses/LICENSE-2.0 [TXT](http://www.apache.org/licenses/LICENSE-2.0.txt) or [HTML](http://www.apache.org/licenses/LICENSE-2.0.html)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
