_ = require 'underscore-plus'
eyaml = require './hiera-eyaml.coffee'
CreateKeysView = require './create-keys-view.coffee'
{Point, Range} = require 'atom'

module.exports =
  config:
    eyamlPath:
      type: 'string'
      default: 'eyaml'
    defaultDir:
      type: 'string'
      default: ''
    publicKeyPath:
      type: 'string'
      default: ''
    privateKeyPath:
      type: 'string'
      default: ''
    messageTimeout:
      type: 'integer'
      default: 5
    wrapEncoded:
      type: 'boolean'
      default: false
    wrapLength:
      type: 'integer'
      default: 60
    indentToColumn:
      type: 'boolean'
      default: false

  activate: (state) ->
    atom.workspaceView.command 'hiera-eyaml:encrypt-selection', => @doSelections eyaml.encrypt
    atom.workspaceView.command 'hiera-eyaml:decrypt-selection', => @doSelections eyaml.decrypt
    atom.workspaceView.command 'hiera-eyaml:create-keys', => @createKeys()

  trim: (str) ->
    str.replace /\s*\n$/, ''

  wrap: (range, text, length) ->
    output = ''
    wrapped = []
    lines = 0
    indent = false
    text = text.replace /^\s*>\s+/, ''
    multiLine = text.split /[\n\r]/

    if multiLine.length > 1
      wrapped = multiLine
      lines = wrapped.length
    else
      while text.length >= (lines * length)
        wrapped.push text.slice lines * length, lines * length + length
        lines++

    startPoint = range.start.copy()
    endPoint = range.end.copy()

    if lines > 1
      output = '>\n'
      output += wrapped.join "\n"
      endPoint.row = startPoint.row + lines
      startPoint.row = startPoint.row + 1
      indent = true
    else
      output = text

    @editor.setTextInBufferRange(range, output)

    if indent
      indentLevel = @editor.indentationForBufferRow(range.start.row)
      tabWidth = @editor.getTabLength()

      if @indentToColumn
        indentLevelNew = startPoint.column / tabWidth
      else
        indentLevelNew = indentLevel + 1

      @indentRows(startPoint, endPoint, indentLevelNew)

  indentRows: (start, end, level=1) ->
    row = start.row
    while row <= end.row
      @editor.setIndentationForBufferRow row, level
      row++

  bufferSetText: (index, crypted) ->
    @count--
    @crypts[index] = crypted

    if @count <= 0
      sorted = _.values(@ranges).sort (a, b) ->
        a.start.compare(b.start)

      @editor.getBuffer().beginTransaction()

      for point in sorted.reverse()
        index = @startPoints[point.start.toString()]
        selection = @ranges[index]
        if @wrapEncoded
          @wrap selection, @crypts[index], @wrapLength
        else
          @editor.setTextInBufferRange selection, @crypts[index]
      @editor.getBuffer().commitTransaction()

  doSelections: (func) ->
    index = 0
    @ranges = {}
    @startPoints = {}
    @crypts = {}
    @wrapEncoded = atom.config.get 'hiera-eyaml.wrapEncoded'
    @wrapLength = atom.config.get 'hiera-eyaml.wrapLength'
    @indentToColumn = atom.config.get 'hiera-eyaml.indentToColumn'

    @editor = atom.workspace.getActiveEditor()

    return if @editor.getRootScopeDescriptor()?[0] != 'source.yaml'

    selectedBufferRanges = @editor.getSelectedBufferRanges()

    ## Remove cursor locations which don't have anything selected
    @realSelections = _.reject selectedBufferRanges, (s) -> s.start.isEqual(s.end)
    @count = @realSelections.length ? 0

    for selectionRange in @realSelections
      index++
      selectedText = @editor.getTextInBufferRange(selectionRange)
      cursorScope = @editor.scopeDescriptorForBufferPosition(selectionRange.start)

      quotedString = _.find(cursorScope, (scope) ->
        if scope in ['string.quoted.single.yaml', 'string.quoted.double.yaml']
          true
        else
          false
      )

      if quotedString?
        startPoint = new Point(selectionRange.start.row, selectionRange.start.column - 1)
        endPoint = new Point(selectionRange.end.row, selectionRange.end.column + 1)
        selectionRange = new Range(startPoint, endPoint)

      @ranges[index] = selectionRange
      @editor.setSelectedBufferRange(selectionRange)

      @startPoints[selectionRange.start.toString()] = index

      func selectedText, index, (idx, cryptedText) =>
        @bufferSetText idx, @trim(cryptedText)

  createKeys: ->
    view = new CreateKeysView()
    view.attach()
