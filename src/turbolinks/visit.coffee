#= require ./http_request

class Turbolinks.Visit
  constructor: (@controller, location, @action) ->
    @promise = new Promise (@resolve, @reject) =>
      @identifier = Turbolinks.uuid()
      @location = Turbolinks.Location.box(location)
      @adapter = @controller.adapter
      @state = "initialized"

  start: ->
    if @state is "initialized"
      @state = "started"
      @adapter.visitStarted(this)
      
  cancel: ->
    if @state is "started"
      @request?.cancel()
      @cancelRender()
      @state = "canceled"

  complete: ->
    if @state is "started"
      @state = "completed"
      @adapter.visitCompleted?(this)
      @resolve()

  fail: ->
    if @state is "started"
      @state = "failed"
      @adapter.visitFailed?(this)
      @reject()

  then: ->
    @promise.then(arguments...)

  catch: ->
    @promise.catch(arguments...)

  changeHistory: ->
    unless @historyChanged
      method = getHistoryMethodForAction(@action)
      @controller[method](@location, @restorationIdentifier)
      @historyChanged = true

  issueRequest: ->
    if @shouldIssueRequest() and not @request?
      @progress = 0
      @request = new Turbolinks.HttpRequest this, @location
      @request.send()

  hasSnapshot: ->
    @controller.hasSnapshotForLocation(@location)

  restoreSnapshot: ->
    if @hasSnapshot() and not @snapshotRestored
      @render ->
        @saveSnapshot()
        if @snapshotRestored = @controller.restoreSnapshotForLocation(@location)
          @scrollToRestoredPosition()
          @adapter.visitSnapshotRestored?(this)
          @complete() unless @shouldIssueRequest()

  loadResponse: ->
    if @response?
      @render ->
        @saveSnapshot()
        if @request.failed
          @controller.loadErrorResponse(@response)
          @scrollToTop()
          @adapter.visitResponseLoaded?(this)
          @fail()
        else
          @controller.loadResponse(@response)
          @scrollToAnchor()
          @adapter.visitResponseLoaded?(this)
          @complete()

  # HTTP Request delegate

  requestStarted: ->
    @adapter.visitRequestStarted?(this)

  requestProgressed: (@progress) ->
    @adapter.visitRequestProgressed?(this)

  requestCompletedWithResponse: (@response) ->
    @adapter.visitRequestCompleted(this)

  requestFailedWithStatusCode: (statusCode, @response) ->
    @adapter.visitRequestFailedWithStatusCode(this, statusCode)

  requestFinished: ->
    @adapter.visitRequestFinished?(this)

  # Scrolling
  
  scrollToTop: ->
    @controller.scrollToPosition(x: 0, y: 0)
  
  scrollToAnchor: ->
    if @location.anchor?
      @controller.scrollToAnchor(@location.anchor)
    else
      @scrollToTop()
  
  scrollToRestoredPosition: ->
    position = @restorationData?.scrollPosition
    if position?
      @controller.scrollToPosition(position)
    else
      @scrollToTop()

  # Private

  getHistoryMethodForAction = (action) ->
    switch action
      when "replace" then "replaceHistoryWithLocationAndRestorationIdentifier"
      when "advance", "restore" then "pushHistoryWithLocationAndRestorationIdentifier"

  shouldIssueRequest: ->
    @action is "advance" or not @hasSnapshot()

  saveSnapshot: ->
    unless @snapshotSaved
      @controller.saveSnapshot()
      @snapshotSaved = true

  render: (callback) ->
    @cancelRender()
    @frame = requestAnimationFrame =>
      @frame = null
      callback.call(this)

  cancelRender: ->
    cancelAnimationFrame(@frame) if @frame
