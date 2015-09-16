mongoose = require('mongoose')
Schema = mongoose.Schema

# Set into an object a value for a nested path like 'prop1.prop2'
setPath = (obj, path, value) ->
    keys = path.split('.')
    lastKey = keys.pop()
    for key in keys
      unless obj[key]?
        obj[key] = {}
      obj = obj[key]
    obj[lastKey] = value

# Supports embedding document at path specified by options.path
# by creating a mixed type field at "#{options.path}#{modelClass.schema.name}" and a
# virtual property that accesses a model specified by options.ref
module.exports = (schema, options = {}) ->

  isSameDocument = (docA, docB) ->
    docA?._id? and docB?._id? and (docA._id.toString() is docB._id.toString())

  newEmbedded = (modelClass, data, parent) ->
    obj = new modelClass(data)
    # Conform to (some of) Mongoose's embedded document API
    obj.__parent = parent
    obj.parent = -> @__parent
    # See https://github.com/LearnBoost/mongoose/issues/1428
    obj.__parentArray = parent
    # Monkey patch embedded object
    # After embedded.set, set the value on our MixedType and mark the parent modified
    setWithoutEmbedded = obj.set
    setWithEmbedded = (args...) ->
      setWithoutEmbedded.apply obj, args
      for path in obj.modifiedPaths()
        embeddedPath = [options.path, path].join '.'
        parent.setValue embeddedPath, obj.getValue(path)
        parent.markModified embeddedPath
    obj.set = setWithEmbedded
    obj

  fields = {}
  fields[options.path] =
    type: Schema.Types.Mixed
    required: options.required? and options.required or false
    get: (data) ->
      return null if !data?

      # Do this lazily help with circular dependencies in the Model definition files.
      modelClass = mongoose.model options.ref, false, false
      propertyName = "#{options.path}#{modelClass.schema.name}"
      @[propertyName] ?= newEmbedded(modelClass, data, @)
    set: (data) ->
      return null if !data?

      # Do this lazily help with circular dependencies in the Model definition files.
      modelClass = mongoose.model options.ref, false, false
      propertyName = "#{options.path}#{modelClass.schema.name}"
      if isSameDocument(@[propertyName], data)
        @[propertyName].set(data.toObject?() or data)
      else
        @[propertyName] = newEmbedded(modelClass, data, @)
      @[propertyName].toJSON()
  schema.add fields
  (schema.__embeddedPaths ?= []).push options.path

  schema.pre 'save', (next) ->
    embedded = @[options.path]
    if !options.dontValidate and embedded?
      # pass any validation errors onto the parent doc's save chain
      embedded.validate (err) =>
        if err
          @errors ?= {}
          for key, value of err.errors
            @errors["#{options.path}.#{key}"] = value
        next(err)
    else
      next()

  schema.post 'init', ->
    embedded = @[options.path]
    embedded?.init(embedded.toJSON())

  schema.post 'save', ->
    embedded = @[options.path]
    embedded?.$__reset()

  schema.method 'toJSON', (options) ->
    result = mongoose.Document.prototype.toJSON.call(@, options)
    if options?.client
      for path in (schema.__embeddedPaths ? [])
        setPath(result, path, @get(path)?.toJSON(options))
    result
