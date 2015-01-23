fibrous = require 'fibrous'
require 'mocha-sinon'
expect = require('chai').expect

mongoose = require 'mongoose'
embeddedDoc = require '..'

mongoose.connect('mongodb://localhost/mongoose_embedded_document')

embeddedSchema = new mongoose.Schema name: String
embeddedSchema.method
  toJSON: (options = {}) ->
    result = @toObject()
    if options.client
      result.clientDiff = 'some client true specific difference'
    result
embeddedSchema.path('name').validate (name) ->
  name?.length >= 3
, 'Name must be 3 or more characters'

Embedded = mongoose.model('Embedded', embeddedSchema)

schema = new mongoose.Schema deep: {}, mixed: {type: mongoose.Schema.Types.Mixed}
schema.plugin embeddedDoc, path: 'embedded', ref: 'Embedded', required: true
schema.plugin embeddedDoc, path: 'deep.embedded', ref: 'Embedded'
TestObject = mongoose.model('TestEmbedded', schema)

describe 'embeddedDoc', ->

  describe 'accessors', ->

    it 'is constructed with the correct api wrt mongoose parent', ->
      emb = new Embedded name: 'Foo'
      expect(emb.parent).to.be.undefined

    it 'gets null', ->
      expect(new TestObject().embedded).to.be.null

    it 'sets model', ->
      emb = new Embedded name: 'Foo'
      obj = new TestObject embedded: emb
      expect(obj.embedded.id).to.eql emb.id
      expect(obj.embedded).not.to.eql emb # to match mongoose behavior
      expect(obj.embedded.parent()).to.equal obj

      emb2 = new Embedded name: 'Bar'
      obj.embedded = emb2
      expect(obj.embedded.id).to.eql emb2.id
      expect(obj.embedded).not.to.eql emb2 # to match mongoose behavior
      expect(obj.embedded.parent()).to.equal obj

    it 'sets json', ->
      emb = { name: 'Foo' }
      obj = new TestObject embedded: emb
      expect(obj.embedded instanceof Embedded).to.be.true
      expect(obj.embedded.name).to.eql 'Foo'
      expect(obj.embedded.parent()).to.equal obj

      obj.set 'embedded', {name: 'Bar'}
      expect(obj.embedded instanceof Embedded).to.be.true
      expect(obj.embedded.name).to.eql 'Bar'
      expect(obj.embedded.parent()).to.equal obj

    it 'gets nested paths', ->
      emb = { name: 'Foo' }
      obj = new TestObject embedded: emb
      expect(obj.get 'embedded.name').to.equal 'Foo'
      obj.embedded.name = 'Bar'
      expect(obj.get 'embedded.name').to.equal 'Bar'

    it 'sets nested paths', ->
      obj = new TestObject mixed: { name: 'Foo'}
      obj.set 'mixed.name', 'Bar'

      expect(obj.mixed.name).to.equal 'Bar'
      expect(obj.get 'mixed.name').to.equal 'Bar'

  describe "save", ->

    # TODO: this should fail but isn't
    xit 'fails validation', ->
      obj = new TestObject()
      obj.sync.save()

    it 'fails embedded validation', fibrous ->
      emb = new Embedded name: 'xx' # Invalid 2 character name
      obj = new TestObject()
      obj.embedded = emb
      expect(-> obj.sync.save()).to.throw()
      expect(obj.errors['embedded.name'].type).to.equal 'Name must be 3 or more characters'

    it 'round trips on save', fibrous ->
      emb = new Embedded name: 'Foo'
      obj = TestObject.sync.create embedded: emb
      saved = TestObject.sync.findById obj
      expect(saved.embedded._id.toString()).to.equal emb._id.toString()
      expect(saved.embedded.name).to.equal emb.name

  describe 'exposes parent property (like a real Mongoose EmbeddedDocument)', ->

    it 'new model (instantiated)', ->
      emb = new Embedded name: 'Foo'
      obj = new TestObject(embedded: emb)
      expect(obj.embedded.__parent).to.eql obj

    it 'new model (json)', ->
      obj = new TestObject(embedded: {name: 'Foo'})
      expect(obj.embedded.__parent).to.eql obj

    it 'persisted model', fibrous ->
      emb = new Embedded name: 'Foo'
      obj = TestObject.sync.create embedded: emb
      saved = TestObject.sync.findById obj
      expect(saved.embedded.__parent).to.eql saved

    it 'setter (object)', ->
      emb = new Embedded name: 'Foo'
      obj = new TestObject()
      obj.embedded = emb
      expect(obj.embedded.__parent).to.eql obj

    it 'setter (json)', ->
      obj = new TestObject()
      obj.embedded = {name: 'Foo'}
      expect(obj.embedded.__parent).to.eql obj

  describe 'supports modification methods', ->
    {obj} = {}

    beforeEach fibrous ->
      obj = TestObject.sync.create embedded: {name: 'Foo'}
      obj = TestObject.sync.findById obj.id # reload
      expect(obj.embedded.isModified()).to.equal false
      expect(obj.embedded.modifiedPaths().length).to.equal 0

    describe 'a property set', ->
      beforeEach ->
        obj.embedded.name = 'momo'

      it '.isModified returns true', ->
        expect(obj.embedded.isModified()).to.equal true
        expect(obj.isModified()).to.equal true

      it '.modifiedPaths', ->
        expect(obj.embedded.modifiedPaths()).to.eql ['name']
        expect(obj.modifiedPaths()).to.eql ['embedded', 'embedded.name']

    describe 'a root set with an object that does not include _id', ->
      beforeEach ->
        obj.embedded = {name: 'Foo'}

      it '.isModified returns true', ->
        expect(obj.embedded.isModified()).to.equal true
        expect(obj.isModified()).to.equal true

      it '.modifiedPaths', ->
        expect(obj.embedded.modifiedPaths()).to.eql ['name']
        expect(obj.modifiedPaths()).to.eql ['embedded']

    describe 'a root set with an unmodified object of the same document', ->
      beforeEach ->
        obj.embedded = obj.embedded.toObject()

      it '.isModified returns false', ->
        expect(obj.embedded.isModified()).to.equal false
        expect(obj.isModified()).to.equal false

      it '.modifiedPaths', ->
        expect(obj.embedded.modifiedPaths()).to.eql []
        expect(obj.modifiedPaths()).to.eql []

    describe 'a root set with a modified object of the same document', ->
      beforeEach ->
        modifiedEmbedded = obj.embedded.toObject()
        modifiedEmbedded.name = 'Bar'
        obj.embedded = modifiedEmbedded

      it '.isModified returns false', ->
        expect(obj.embedded.isModified()).to.equal true
        expect(obj.isModified()).to.equal true

      it '.modifiedPaths', ->
        expect(obj.embedded.modifiedPaths()).to.eql ['name']
        expect(obj.modifiedPaths()).to.eql ['embedded', 'embedded.name']

    describe 'a root set with an unmodified mongoose model of the same document', ->
      beforeEach fibrous ->
        embeddedClone = TestObject.sync.findById(obj).embedded
        obj.embedded = embeddedClone

      it '.isModified returns false', ->
        expect(obj.embedded.isModified()).to.equal false
        expect(obj.isModified()).to.equal false

      it '.modifiedPaths', ->
        expect(obj.embedded.modifiedPaths()).to.eql []
        expect(obj.modifiedPaths()).to.eql []

    describe 'a root set with a modified mongoose model of the same document', ->
      beforeEach fibrous ->
        embeddedClone = TestObject.sync.findById(obj).embedded
        embeddedClone.name = 'Bar'
        obj.embedded = embeddedClone

      it '.isModified returns false', ->
        expect(obj.embedded.isModified()).to.equal true
        expect(obj.isModified()).to.equal true

      it '.modifiedPaths', ->
        expect(obj.embedded.modifiedPaths()).to.eql ['name']
        expect(obj.modifiedPaths()).to.eql ['embedded', 'embedded.name']

    describe 'a root set with an object of a different document', ->
      beforeEach ->
        obj.embedded = new Embedded(name: 'Foo').toJSON()

      it '.isModified returns true', ->
        expect(obj.embedded.isModified()).to.equal true
        expect(obj.isModified()).to.equal true

      it '.modifiedPaths', ->
        expect(obj.embedded.modifiedPaths()).to.eql ['_id', 'name']
        expect(obj.modifiedPaths()).to.eql ['embedded']

    describe 'after save', ->
      {saved} = {}
      beforeEach fibrous ->
        obj.embedded.name = 'momo'
        obj.sync.save()
        saved = TestObject.sync.findById obj.id

      it '#isModified', ->
        expect(obj.embedded.isModified()).to.equal false
        expect(obj.isModified()).to.equal false

      it '#modifiedPaths', ->
        expect(obj.embedded.modifiedPaths().length).to.equal 0

      it 'saves modified value', ->
        expect(saved.embedded.name).to.equal 'momo'

  describe 'toJSON', ->
    it 'passes the client: true option to any embedded doc', ->
      emb = new Embedded name: 'Foo'
      obj = new TestObject embedded: emb
      expect(obj.toJSON().embedded.clientDiff).to.be.undefined
      expect(obj.toJSON(client: true).embedded.clientDiff).to.eql 'some client true specific difference'

    it 'properly handles null versions of embedded docs', ->
      obj = new TestObject()
      expect(obj.toJSON(client: true).embedded).to.be.undefined

    it 'handles deep embed', ->
      emb = new Embedded name: 'Foo'
      obj = new TestObject deep: embedded: emb
      expect(obj.toJSON(client: true).deep.embedded.name).to.eql 'Foo'
      expect(obj.toJSON(client: true)['deep.embedded']).to.be.undefined

  # Verifies a bugfix that ensureIndex is not called on models for embedded documents
  describe 'ensureIndex', ->
    beforeEach ->
      @sinon.stub(Embedded, 'ensureIndexes')

    it 'ensureIndex is not called', ->
      emb = new Embedded name: 'Foo'
      obj = new TestObject embedded: emb
      expect(Embedded.ensureIndexes).not.to.have.been.called

