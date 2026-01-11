# adb-hass-androidtv

## Overview
Connect to and control androidtv/firetv/googletv devices through ADB.

This image will start an ADB (Android Debug Bridge) server listening on port 5037 and connect to a list of specified androidtv/firetv/googletv devices over the network. This will allow you to integrate them with [Home Assistant](https://www.home-assistant.io/) using the [AndroidTV integration](https://www.home-assistant.io/integrations/androidtv/).

## Features
- Quick and easy connection to Android based devices over the network.
- Lightweight Alpine based image.
- Supports environment variable configuration.
- Support for devices based up to Android 11.

## Usage

### Docker

Run in docker, using environment variables:
```shell
docker run -it -e devicelist=192.168.1.100,192.168.1.101::739264:44556 -e bootwait=10 -e checkfreq=60 barnybbb/adb-hass-androidtv:latest
```

Docker compose, using environment variables:
```yml
services:
  adb-hass-androidtv:
    image: barnybbb/adb-hass-androidtv:latest
    hostname: adb-hass-androidtv.local
    container_name: adb-hass-androidtv
    ports:
      - 5037:5037
    environment:
      devicelist: 192.168.1.100,192.168.1.101::739264:44556
      bootwait: 10
      checkfreq: 60
    restart: unless-stopped
```

### UnRAID

You can use the UnRAID Community Template provided here: 

## Configuration

### Configuration Options

These can be specified as environment variables.

| config option | default | required | description |
|--|--|--|--|
| devicelist | n/a | yes | List of Android device(s) to connect to and their connection settings |
| bootwait | 10 | no | Time to wait (in seconds) for before attempting connection to device(s) at container init |
| checkfreq | 60 | no | Frequency (in seconds) to check device(s) connection status |

For the environment variable `devicelist` must be a comma separated list of devices specified in the following format:

`<host>:[<port>]`

- `<port>` is optional and if not specified will default to `5555`

Examples:

- `192.168.1.100` - specify a single device, will default to connect to ADB port 5555
- `192.168.1.100:5555,192.168.101:5555` - specify two devices, both connecting to ADB port 5555

### Home Assistant
Configure your Home Assistant instance in the `configuration.yaml` file with:

```yml
media_player:
  - platform: androidtv
    name: Fire TV
    device_class: firetv
    host: 192.168.1.100
    port: 5555
    adb_server_ip: [ip of the barnybbb/adb-hass-androidtv container]
    adb_server_port: 5037
  - platform: androidtv
    name: Fire TV
    device_class: firetv
    host: 192.168.1.101
    port: 5555
    adb_server_ip: [ip of the barnybbb/adb-hass-androidtv container]
    adb_server_port: 5037
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## GitHub Project

[BLBurgess/adb-hass-androidtv](https://github.com/BLBurgess/adb-hass-androidtv)

## Version History

| Image Version | Release Date | Alpine Version | ADB Version | Release Notes |
|---|---|---|---|---|
| 1.0.0 | 2020-12-22 | 3.22.0 | 29.0.6-6198805 | [See CHANGELOG](CHANGELOG.md#100-2020-12-22) |
