
# TODO: This shouldn't need to be included, but should ideally be exported.
type
  FutureBase* = ref object of RootObj ## Untyped future.
    cb: proc () {.closure,gcsafe.}
    finished: bool
    error*: ref Exception ## Stored exception
    errorStackTrace*: string
    when not defined(release):
      stackTrace: string ## For debugging purposes only.
      id: int
      fromProc: string

  Future*[T] = ref object of FutureBase ## Typed future.
    value: T ## Stored value

  FutureVar*[T] = distinct Future[T]

  FutureStream*[T] = ref object of FutureBase   ## Special future that acts as
                                                ## a queue. Its API is still
                                                ## experimental and so is
                                                ## subject to change.
    queue: Deque[T]

  FutureError* = object of Exception
    cause*: FutureBase

{.deprecated: [PFutureBase: FutureBase, PFuture: Future].}

when not defined(release):
  var currentID = 0

proc callSoon*(cbproc: proc ()) {.gcsafe.}

template setupFutureBase(fromProc: string) =
  new(result)
  result.finished = false
  when not defined(release):
    result.stackTrace = getStackTrace()
    result.id = currentID
    result.fromProc = fromProc
    currentID.inc()

proc newFuture*[T](fromProc: string = "unspecified"): Future[T] =
  ## Creates a new future.
  ##
  ## Specifying ``fromProc``, which is a string specifying the name of the proc
  ## that this future belongs to, is a good habit as it helps with debugging.
  setupFutureBase(fromProc)

proc newFutureVar*[T](fromProc = "unspecified"): FutureVar[T] =
  ## Create a new ``FutureVar``. This Future type is ideally suited for
  ## situations where you want to avoid unnecessary allocations of Futures.
  ##
  ## Specifying ``fromProc``, which is a string specifying the name of the proc
  ## that this future belongs to, is a good habit as it helps with debugging.
  result = FutureVar[T](newFuture[T](fromProc))

proc newFutureStream*[T](fromProc = "unspecified"): FutureStream[T] =
  ## Create a new ``FutureStream``. This future's callback is activated when
  ## two events occur:
  ##
  ## * New data is written into the future stream.
  ## * The future stream is completed (this means that no more data will be
  ##   written).
  ##
  ## Specifying ``fromProc``, which is a string specifying the name of the proc
  ## that this future belongs to, is a good habit as it helps with debugging.
  ##
  ## **Note:** The API of FutureStream is still new and so has a higher
  ## likelihood of changing in the future.
  setupFutureBase(fromProc)
  result.queue = initDeque[T]()

proc clean*[T](future: FutureVar[T]) =
  ## Resets the ``finished`` status of ``future``.
  Future[T](future).finished = false
  Future[T](future).error = nil

proc checkFinished[T](future: Future[T]) =
  ## Checks whether `future` is finished. If it is then raises a
  ## ``FutureError``.
  when not defined(release):
    if future.finished:
      var msg = ""
      msg.add("An attempt was made to complete a Future more than once. ")
      msg.add("Details:")
      msg.add("\n  Future ID: " & $future.id)
      msg.add("\n  Created in proc: " & future.fromProc)
      msg.add("\n  Stack trace to moment of creation:")
      msg.add("\n" & indent(future.stackTrace.strip(), 4))
      when T is string:
        msg.add("\n  Contents (string): ")
        msg.add("\n" & indent(future.value.repr, 4))
      msg.add("\n  Stack trace to moment of secondary completion:")
      msg.add("\n" & indent(getStackTrace().strip(), 4))
      var err = newException(FutureError, msg)
      err.cause = future
      raise err

proc complete*[T](future: Future[T], val: T) =
  ## Completes ``future`` with value ``val``.
  #assert(not future.finished, "Future already finished, cannot finish twice.")
  checkFinished(future)
  assert(future.error == nil)
  future.value = val
  future.finished = true
  if future.cb != nil:
    future.cb()

proc complete*(future: Future[void]) =
  ## Completes a void ``future``.
  #assert(not future.finished, "Future already finished, cannot finish twice.")
  checkFinished(future)
  assert(future.error == nil)
  future.finished = true
  if future.cb != nil:
    future.cb()

proc complete*[T](future: FutureVar[T]) =
  ## Completes a ``FutureVar``.
  template fut: untyped = Future[T](future)
  checkFinished(fut)
  assert(fut.error == nil)
  fut.finished = true
  if fut.cb != nil:
    fut.cb()

proc complete*[T](future: FutureVar[T], val: T) =
  ## Completes a ``FutureVar`` with value ``val``.
  ##
  ## Any previously stored value will be overwritten.
  template fut: untyped = Future[T](future)
  checkFinished(fut)
  assert(fut.error.isNil())
  fut.finished = true
  fut.value = val
  if not fut.cb.isNil():
    fut.cb()

proc complete*[T](future: FutureStream[T]) =
  ## Completes a ``FutureStream`` signalling the end of data.
  future.finished = true
  if not future.cb.isNil():
    future.cb()

proc fail*[T](future: Future[T], error: ref Exception) =
  ## Completes ``future`` with ``error``.
  #assert(not future.finished, "Future already finished, cannot finish twice.")
  checkFinished(future)
  future.finished = true
  future.error = error
  future.errorStackTrace =
    if getStackTrace(error) == "": getStackTrace() else: getStackTrace(error)
  if future.cb != nil:
    future.cb()
  else:
    # This is to prevent exceptions from being silently ignored when a future
    # is discarded.
    # TODO: This may turn out to be a bad idea.
    # Turns out this is a bad idea.
    #raise error
    discard

proc `callback=`*(future: FutureBase, cb: proc () {.closure,gcsafe.}) =
  ## Sets the callback proc to be called when the future completes.
  ##
  ## If future has already completed then ``cb`` will be called immediately.
  ##
  ## **Note**: You most likely want the other ``callback`` setter which
  ## passes ``future`` as a param to the callback.
  future.cb = cb
  if future.finished:
    callSoon(future.cb)

proc `callback=`*[T](future: Future[T],
    cb: proc (future: Future[T]) {.closure,gcsafe.}) =
  ## Sets the callback proc to be called when the future completes.
  ##
  ## If future has already completed then ``cb`` will be called immediately.
  future.callback = proc () = cb(future)

proc `callback=`*[T](future: FutureStream[T],
    cb: proc (future: FutureStream[T]) {.closure,gcsafe.}) =
  ## Sets the callback proc to be called when data was placed inside the
  ## future stream.
  ##
  ## The callback is also called when the future is completed. So you should
  ## use ``finished`` to check whether data is available.
  ##
  ## If the future stream already has data or is finished then ``cb`` will be
  ## called immediately.
  future.cb = proc () = cb(future)
  if future.queue.len > 0 or future.finished:
    callSoon(future.cb)

proc injectStacktrace[T](future: Future[T]) =
  # TODO: Come up with something better.
  when not defined(release):
    var msg = ""
    msg.add("\n  " & future.fromProc & "'s lead up to read of failed Future:")

    if not future.errorStackTrace.isNil and future.errorStackTrace != "":
      msg.add("\n" & indent(future.errorStackTrace.strip(), 4))
    else:
      msg.add("\n    Empty or nil stack trace.")
    future.error.msg.add(msg)

proc read*[T](future: Future[T] | FutureVar[T]): T =
  ## Retrieves the value of ``future``. Future must be finished otherwise
  ## this function will fail with a ``ValueError`` exception.
  ##
  ## If the result of the future is an error then that error will be raised.
  {.push hint[ConvFromXtoItselfNotNeeded]: off.}
  let fut = Future[T](future)
  {.pop.}
  if fut.finished:
    if fut.error != nil:
      injectStacktrace(fut)
      raise fut.error
    when T isnot void:
      return fut.value
  else:
    # TODO: Make a custom exception type for this?
    raise newException(ValueError, "Future still in progress.")

proc readError*[T](future: Future[T]): ref Exception =
  ## Retrieves the exception stored in ``future``.
  ##
  ## An ``ValueError`` exception will be thrown if no exception exists
  ## in the specified Future.
  if future.error != nil: return future.error
  else:
    raise newException(ValueError, "No error in future.")

proc mget*[T](future: FutureVar[T]): var T =
  ## Returns a mutable value stored in ``future``.
  ##
  ## Unlike ``read``, this function will not raise an exception if the
  ## Future has not been finished.
  result = Future[T](future).value

proc finished*[T](future: Future[T] | FutureVar[T] | FutureStream[T]): bool =
  ## Determines whether ``future`` has completed.
  ##
  ## ``True`` may indicate an error or a value. Use ``failed`` to distinguish.
  ##
  ## For a ``FutureStream`` a ``true`` value means that no more data will be
  ## placed inside the stream _and_ that there is no data waiting to be
  ## retrieved.
  when future is FutureVar[T]:
    result = (Future[T](future)).finished
  elif future is FutureStream[T]:
    result = future.finished and future.queue.len == 0
  else:
    result = future.finished

proc failed*(future: FutureBase): bool =
  ## Determines whether ``future`` completed with an error.
  return future.error != nil

proc write*[T](future: FutureStream[T], value: T): Future[void] =
  ## Writes the specified value inside the specified future stream.
  ##
  ## This will raise ``ValueError`` if ``future`` is finished.
  result = newFuture[void]("FutureStream.put")
  if future.finished:
    let msg = "FutureStream is finished and so no longer accepts new data."
    result.fail(newException(ValueError, msg))
    return
  # TODO: Implement limiting of the streams storage to prevent it growing
  # infinitely when no reads are occuring.
  future.queue.addLast(value)
  if not future.cb.isNil: future.cb()
  result.complete()

proc read*[T](future: FutureStream[T]): Future[(bool, T)] =
  ## Returns a future that will complete when the ``FutureStream`` has data
  ## placed into it. The future will be completed with the oldest
  ## value stored inside the stream. The return value will also determine
  ## whether data was retrieved, ``false`` means that the future stream was
  ## completed and no data was retrieved.
  ##
  ## This function will remove the data that was returned from the underlying
  ## ``FutureStream``.
  var resFut = newFuture[(bool, T)]("FutureStream.take")
  let savedCb = future.cb
  future.callback =
    proc (fs: FutureStream[T]) =
      # We don't want this callback called again.
      future.cb = nil

      # The return value depends on whether the FutureStream has finished.
      var res: (bool, T)
      if finished(fs):
        # Remember, this callback is called when the FutureStream is completed.
        res[0] = false
      else:
        res[0] = true
        res[1] = fs.queue.popFirst()

      if not resFut.finished:
        resFut.complete(res)

      # If the saved callback isn't nil then let's call it.
      if not savedCb.isNil: savedCb()
  return resFut

proc len*[T](future: FutureStream[T]): int =
  ## Returns the amount of data pieces inside the stream.
  future.queue.len

proc asyncCheck*[T](future: Future[T]) =
  ## Sets a callback on ``future`` which raises an exception if the future
  ## finished with an error.
  ##
  ## This should be used instead of ``discard`` to discard void futures.
  future.callback =
    proc () =
      if future.failed:
        injectStacktrace(future)
        raise future.error

proc `and`*[T, Y](fut1: Future[T], fut2: Future[Y]): Future[void] =
  ## Returns a future which will complete once both ``fut1`` and ``fut2``
  ## complete.
  var retFuture = newFuture[void]("asyncdispatch.`and`")
  fut1.callback =
    proc () =
      if not retFuture.finished:
        if fut1.failed: retFuture.fail(fut1.error)
        elif fut2.finished: retFuture.complete()
  fut2.callback =
    proc () =
      if not retFuture.finished:
        if fut2.failed: retFuture.fail(fut2.error)
        elif fut1.finished: retFuture.complete()
  return retFuture

proc `or`*[T, Y](fut1: Future[T], fut2: Future[Y]): Future[void] =
  ## Returns a future which will complete once either ``fut1`` or ``fut2``
  ## complete.
  var retFuture = newFuture[void]("asyncdispatch.`or`")
  proc cb[X](fut: Future[X]) =
    if fut.failed: retFuture.fail(fut.error)
    if not retFuture.finished: retFuture.complete()
  fut1.callback = cb[T]
  fut2.callback = cb[Y]
  return retFuture

proc all*[T](futs: varargs[Future[T]]): auto =
  ## Returns a future which will complete once
  ## all futures in ``futs`` complete.
  ## If the argument is empty, the returned future completes immediately.
  ##
  ## If the awaited futures are not ``Future[void]``, the returned future
  ## will hold the values of all awaited futures in a sequence.
  ##
  ## If the awaited futures *are* ``Future[void]``,
  ## this proc returns ``Future[void]``.

  when T is void:
    var
      retFuture = newFuture[void]("asyncdispatch.all")
      completedFutures = 0

    let totalFutures = len(futs)

    for fut in futs:
      fut.callback = proc(f: Future[T]) =
        inc(completedFutures)
        if not retFuture.finished:
          if f.failed:
            retFuture.fail(f.error)
          else:
            if completedFutures == totalFutures:
              retFuture.complete()

    if totalFutures == 0:
      retFuture.complete()

    return retFuture

  else:
    var
      retFuture = newFuture[seq[T]]("asyncdispatch.all")
      retValues = newSeq[T](len(futs))
      completedFutures = 0

    for i, fut in futs:
      proc setCallback(i: int) =
        fut.callback = proc(f: Future[T]) =
          inc(completedFutures)
          if not retFuture.finished:
            if f.failed:
              retFuture.fail(f.error)
            else:
              retValues[i] = f.read()

              if completedFutures == len(retValues):
                retFuture.complete(retValues)

      setCallback(i)

    if retValues.len == 0:
      retFuture.complete(retValues)

    return retFuture
