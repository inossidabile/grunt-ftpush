require 'sugar'

Path   = require 'path'
FS     = require 'fs'
FTP    = require 'jsftp'
async  = require 'async'
util   = require 'util'
crypto = require 'crypto'

module.exports = (grunt) ->

  grunt.registerMultiTask "ftpush", "Mirror code over FTP", (target) ->
    done = @async()
    
    auth = (key) ->
      if grunt.file.exists(".ftppass")
        config = grunt.file.read(".ftppass")
        return JSON.parse(config)[key] if key? and config.length

    grunt.log.debug "Collecting information..."

    localRoot   = if Array.isArray(@data.src) then @data.src[0] else @data.src
    remoteRoot  = if Array.isArray(@data.dest) then @data.dest[0] else @data.dest
    credentials = if @data.auth.authKey then auth(@data.auth.authKey) else auth(@data.auth.host)
    exclusions  = @data.exclusions || []
    keep        = @data.keep || []
    options     =
      useList: !!@data.useList
      remove:  !(grunt.option('simple') || @data.simple)

    grunt.log.debug "Initializing synchronizer..."

    sync = new Synchronizer(
      localRoot,
      remoteRoot,
      Path.join(".grunt", "ftpush", "#{@target}.json"),
      Object.merge(@data.auth, credentials),
      exclusions,
      keep,
      options
    )

    grunt.log.debug "Synchronizer initialized..."

    sync.sync done

  class Synchronizer

    debug: false

    constructor: (@localRoot, @remoteRoot, @memoryPath, @auth, @exclusions, @keep, options) ->
      @localRoot = Path.resolve(@localRoot)
      grunt.log.debug "Local root set to '#{@localRoot}'"

      @localFiles = @buildTree()
      grunt.log.debug "#{Object.keys(@localFiles).length} paths found"

      @remove = options.remove

      @ftp = new FTP
        host: @auth.host
        port: @auth.port
      @ftp.useList = options.useList

      @memory = if grunt.file.exists(@memoryPath)
        JSON.parse grunt.file.read(@memoryPath)
      else
        {}

    normalizeFtpPath: (path) ->
      path.split(Path.sep).join('/')

    hash: (path) ->
      hash = crypto.createHash 'md5'
      hash.update grunt.file.read(path)
      hash.digest 'hex'

    remember: (path, file, hash) ->
      @memory[path] ||= {}
      @memory[path][file] = hash
      grunt.file.write @memoryPath, JSON.stringify(@memory)

    prepare: (callback) ->
      @ftp.auth @auth.username, @auth.password, (err) =>
        grunt.fatal "Authentication error: #{err}" if err
        grunt.log.ok "Authenticated as #{@auth.username}"
        callback()

    sync: (callback) ->
      grunt.log.debug "Uploading started..."

      finish = (err) =>
        grunt.warn err if err
        @ftp.raw.quit ->
          callback()

      @prepare =>
        if @remove
          grunt.log.debug "Switching to full synchronization mode..."

          diff = (path, done) =>
            @diff path, (diff) =>
              @perform path, diff, ->
                done()

          async.each Object.keys(@localFiles), diff, finish
        else
          grunt.log.debug "Switching to simple mode..."

          commands = []
          files    = @findLocallyModified()

          upload = (path, done) =>
            @touchRecursive Path.join(@remoteRoot, path), =>
              files[path].each (file) =>
                commands.push (done) =>
                  @upload file.name, path, file.hash, done
              done()

          async.each Object.keys(files), upload, =>
            async.parallel commands, finish

    perform: (path, diff, callback) ->
      commands = []

      diff.upload.each (entry) =>
        commands.push (done) =>
          @upload entry[0], path, entry[1], done

      diff.rm.each (basename) =>
        commands.push (done) =>
          @rm basename, path, done

      diff.rmDir.each (basename) =>
        commands.push (done) =>
          @rmDir basename, path, done

      async.parallel commands, ->
        callback()

    buildTree: (root=@localRoot, result={}) ->
      result[Path.sep] ||= []
      
      unless grunt.file.exists(root)
        grunt.fatal "#{root} is not an existing location"  
      
      for filename in FS.readdirSync(root)
        path = Path.join(root, filename)

        unless grunt.file.isMatch({matchBase: true}, @exclusions, Path.relative(@localRoot, path))
          if grunt.file.isDir path
            grunt.log.debug "Building tree: Recursing into #{path}"
            result[Path.sep + Path.relative(@localRoot, path)] ||= []
            @buildTree(path, result)
          else
            grunt.log.debug "Building tree: Added #{path}"
            result[Path.sep + Path.relative(@localRoot, root)].push
              name: filename
              hash: @hash(path)

      result

    findLocallyModified: ->
      changed = {}

      Object.each @localFiles, (path, files) =>
        for file in files
          if file.hash != @memory[path]?[file.name]
            changed[path] ||= []
            changed[path].push file

      changed

    diff: (path, callback) ->
      localFiles = @localFiles[path]

      @touch Path.join(@remoteRoot, path), (remoteFiles) =>
        diff =
          upload: []
          rm:     []
          rmDir:  []

        remoteFiles.each (rf) =>
          rf.name = Path.basename(rf.name)

          unless grunt.file.isMatch({matchBase: true}, @keep, Path.join(path, rf.name))
            # File
            if rf.type == 0
              lf = localFiles.find (x) -> rf.name == x.name
              diff.rm.push rf.name if !lf
            # Directory
            else if rf.type == 1
              diff.rmDir.push rf.name if !@localFiles[Path.join(path, rf.name)]

        localFiles.each (lf) =>
          rf = remoteFiles.find (x) -> lf.name == x.name
          diff.upload.push [lf.name, lf.hash] if !rf || lf.hash != @memory[path]?[lf.name]

        grunt.log.ok "Got diff for #{path.yellow} #{diff.upload.length.toString().green} #{diff.rm.length.toString().red} #{diff.rmDir.length.toString().cyan}"
        grunt.log.debug "Diff", util.inspect(diff)
        callback(diff)

    touchRecursive: (path, callback) ->
      segments = path.split(Path.sep)
      step     = []
      commands = []

      for segment in segments when segment.length > 0
        do (segment) =>
          step.push segment
          localPath = step.join Path.sep
          commands.push (done) => @touch localPath, done

      async.parallel commands, callback


    touch: (path, callback) ->
      grunt.log.debug "Touch", util.inspect(path)

      @ftp.ls @normalizeFtpPath(path), (err, results) =>
        return callback(results.compact()) if !err && results?.length? && results.length > 0

        grunt.log.debug "Make directory", util.inspect(path)

        @ftp.raw.mkd @normalizeFtpPath(path), (err) =>
          if err
            grunt.log.debug "Remote folder wasn't creted (isn't empty?) " + path + " --> " + err
          else
            grunt.log.ok "New remote folder created " + path.yellow

          callback([])
    
    upload: (basename, path, hash, callback) ->
      grunt.log.debug "Upload", util.inspect(basename), util.inspect(path), util.inspect(hash)

      remoteFile = @normalizeFtpPath Path.join(@remoteRoot, path, basename)

      @ftp.put remoteFile, FS.readFileSync(Path.join @localRoot, path, basename), (err) =>
        if err
          grunt.warn "Cannot upload file: " + basename + " --> " + err
        else
          @remember path, basename, hash
          grunt.log.ok "Uploaded file: " + basename.green + " to: " + path.yellow
          callback()

    rm: (basename, path, callback) ->
      grunt.log.debug "Delete", util.inspect(basename), util.inspect(path)

      @ftp.raw.dele @normalizeFtpPath(Path.join @remoteRoot, path, basename), (err) ->
        if err
          grunt.warn "Cannot delete file: " + basename + " --> " + err
        else
          grunt.log.ok "Removed file: " + basename.green + " from: " + path.yellow
          callback()

    rmDir: (basename, path, callback) ->
      grunt.log.debug "Delete directory", util.inspect(basename), util.inspect(path)

      remotePath = @normalizeFtpPath Path.join(@remoteRoot, path, basename)

      @ftp.ls remotePath, (err, results) =>
        grunt.warn "Cannot list directory #{remotePath} for removal --> #{err}" if err

        commands = []

        results.compact().each (rf) =>
          if rf.type == 0
            commands.push (done) =>
              @rm rf.name, Path.join(path, basename), done
          else
            commands.push (done) =>
              @rmDir rf.name, Path.join(path, basename), done

        async.parallel commands, =>
          @ftp.raw.rmd remotePath, (err) =>
            grunt.warn "Cannot remove directory #{remotePath} --> #{err}" if err
            grunt.log.ok "Removed directory: " + basename.green + " from: " + path.yellow
            callback()