# grunt-ftpush

[![NPM version](https://badge.fury.io/js/grunt-ftpush.png)](http://badge.fury.io/js/grunt-ftpush)

> Incrementally deploy data over the FTP protocol.
>
> Being rewrite of [grunt-ftp-deploy](https://github.com/zonak/grunt-ftp-deploy) it works incrementally
> unlike its predecessor. It mirrors remote location to the given local location removing excess directories
> and files. Additionally it tries to intellectually upload only changed files.

**NOTE**: with the limited abilities of FTP, the only adequate way to track changes is to track them locally. It means that each run will compare set of files **to the previous run** and not the server state. Therefore:

  * The first run will upload everything since we have no idea what's the state of a server. Current state will be saved to `.grunt/ftpush`.
  * If there are two users that deploy (or you use multiple machines), it will increment _all_ local changes. It can be considered safe but you might end up uploading a bit more.
  * To make it reupload from the scratch, delete files located at `.grunt/ftpush/*`.

## ATTENTION

This plugin is based on `jsftp` which may sometimes be pretty unstable. I will try hard to help you but its behavior may differ depending on the FTP server you connect to and I can't test them all.

**Please consider the constant usage of `--simple` mode before raising an issue.**

In this mode ftpush won't delete any excessive files on the server. It won't even try to list what's on the server. Instead it will just make incremental upload of files that actually changed (which is probably the main thing you want).

If it works for you – add `simple: true` to your config and that's it!

## Getting Started
This plugin requires Grunt `~0.4.0`

If you haven't used [Grunt](http://gruntjs.com/) before, be sure to check out the [Getting Started](http://gruntjs.com/getting-started) guide, as it explains how to create a [Gruntfile](http://gruntjs.com/sample-gruntfile) as well as install and use Grunt plugins. Once you're familiar with that process, you may install this plugin with this command:

```shell
npm install grunt-ftpush --save-dev
```

Once the plugin has been installed, it may be enabled inside your Gruntfile with this line of JavaScript:

```js
grunt.loadNpmTasks('grunt-ftpush');
```

## How to use

Within your Grunt configuration you have to define one or more bundles to upload:

```javascript
ftpush: {
  build: {
    auth: {
      host: 'server.com',
      port: 21,
      authKey: 'key1'
    },
    src: 'path/to/source/folder',
    dest: '/path/to/destination/folder',
    exclusions: ['path/to/source/folder/**/.DS_Store', 'path/to/source/folder/**/Thumbs.db', 'dist/tmp'],
    keep: ['/important/images/at/server/*.jpg']
  }
}
```

The possible parameters of the configuration are:

- **host** - the name or the IP address of the server we are deploying to
- **port** - the port that the _ftp_ service is running on
- **authKey** - a key for looking up the saved credentials. If no value is defined, the `host` parameter will be used
- **src** - the source location, the local folder that we are transferring to the server
- **dest** - the destination location, the folder on the server we are deploying to
- **exclusions** - an optional parameter allowing us to exclude files and folders by utilizing grunt's support for `minimatch`. Please note that the definitions should be relative to the project root
- **keep** - an array of paths that should be kept on the server even when they are not presented locally. The definitions should be relative to `dest`.
- **simple** - if set to `true`, task will upload modified files and quit, it will NOT remove redundant files and directories at the server side.

## Options

The only possible option is: `--simple`. If given, task will upload modified files and quit, it will NOT remove redundant files and directories at the server side.

## Authentication parameters

Usernames and passwords are stored as a JSON object in a file named `.ftppass`. This file should be located in the same folder as your `Gruntfile`. `.ftppass` should have the following format:

```javascript
{
  "key1": {
    "username": "username1",
    "password": "password1"
  },
  "key2": {
    "username": "username2",
    "password": "password2"
  }
}
```

This way we can save as many username / password combinations as we want and look them up by the `authKey` value defined in the _grunt_ config file where the rest of the target parameters are defined.

**IMPORTANT**: make sure that the `.ftppass` file uses double quotes (which is the proper _JSON_ syntax) instead of single quotes for the names of the keys and the string values.

## Kudos

This task is a fork of [grunt-ftp-deploy](https://github.com/zonak/grunt-ftp-deploy) by [zonak](https://github.com/zonak).

It also is built by taking advantage of the great work of Sergi Mansilla and his [jsftp](https://github.com/sergi/jsftp) _node.js_ module and suited for the **0.4.x** branch of _grunt_.

## Maintainers

* Boris Staal, [@inossidabile](http://staal.io)

## License

It is free software, and may be redistributed under the terms of MIT license.

[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/inossidabile/grunt-ftpush/trend.png)](https://bitdeli.com/free "Bitdeli Badge")