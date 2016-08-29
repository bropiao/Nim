Version 0.15.0 released
=======================

.. container:: metadata

  Posted by Dominik Picheta on 17/09/2016

Some text here.

Changes affecting backwards compatibility
-----------------------------------------

- The ``json`` module uses an ``OrderedTable`` rather than a ``Table``
  for JSON objects.
- De-deprecated ``re.nim`` because we have too much code using it
  and it got the basic API right.

- ``split`` with ``set[char]`` as a delimiter in ``strutils.nim``
  no longer strips and splits characters out of the target string
  by the entire set of characters. Instead, it now behaves in a
  similar fashion to ``split`` with ``string`` and ``char``
  delimiters. Use ``splitWhitespace`` to get the old behaviour.
- The command invocation syntax will soon apply to open brackets
  and curlies too. This means that code like ``a [i]`` will be
  interpreted as ``a([i])`` and not as ``a[i]`` anymore. Likewise
  ``f (a, b)`` means that the tuple ``(a, b)`` is passed to ``f``.
  The compiler produces a warning for ``a [i]``::

    Warning: a [b] will be parsed as command syntax; spacing is deprecated

  See `<https://github.com/nim-lang/Nim/issues/3898>`_ for the relevant
  discussion.
- Overloading the special operators ``.``, ``.()``, ``.=``, ``()`` now
  should be enabled via ``{.experimental.}``.
- ``immediate`` templates and macros are now deprecated.
  Instead use ``untyped`` parameters.
- The metatype ``expr`` is deprecated. Use ``untyped`` instead.
- The metatype ``stmt`` is deprecated. Use ``typed`` instead.
- The compiler is now more picky when it comes to ``tuple`` types. The
  following code used to compile, now it's rejected:

.. code-block:: nim

  import tables
  var rocketaims = initOrderedTable[string, Table[tuple[k: int8, v: int8], int64] ]()
  rocketaims["hi"] = {(-1.int8, 0.int8): 0.int64}.toTable()

Instead be consistent in your tuple usage and use tuple names for tuples
that have tuple name:

.. code-block:: nim

  import tables
  var rocketaims = initOrderedTable[string, Table[tuple[k: int8, v: int8], int64] ]()
  rocketaims["hi"] = {(k: -1.int8, v: 0.int8): 0.int64}.toTable()

- Now when you compile console application for Windows, console output
  encoding is automatically set to UTF-8.

- Unhandled exceptions in JavaScript are now thrown regardless ``noUnhandledHandler``
  is defined. But now they do their best to provide a readable stack trace.

- In JavaScript ``system.alert`` is deprecated. Use ``dom.alert`` instead.

Library Additions
-----------------

- Added ``readHeaderRow`` and ``rowEntry`` to ``parsecsv.nim`` to provide
  a lightweight alternative to python's ``csv.DictReader``.
- Added ``setStdIoUnbuffered`` proc to ``system.nim`` to enable unbuffered I/O.

- Added ``center`` and ``rsplit`` to ``strutils.nim`` to
  provide similar Python functionality for Nim's strings.

- Added ``isTitle``, ``title``, ``swapCase``, ``isUpper``, ``toUpper``,
  ``isLower``, ``toLower``, ``isAlpha``, ``isSpace``, and ``capitalize``
  to ``unicode.nim`` to provide unicode aware case manipulation and case
  testing.

- Added a new module ``lib/pure/strmisc.nim`` to hold uncommon string
  operations. Currently contains ``partition``, ``rpartition``
  and ``expandTabs``.

- Split out ``walkFiles`` in ``os.nim`` to three separate procs in order
  to make a clear distinction of functionality. ``walkPattern`` iterates
  over both files and directories, while ``walkFiles`` now only iterates
  over files and ``walkDirs`` only iterates over directories.

Compiler Additions
------------------

- The ``-d/--define`` flag can now optionally take a value to be used
  by code at compile time.

Nimscript Additions
-------------------

- Finally it's possible to dis/enable specific hints and warnings in
  Nimscript via the procs ``warning`` and ``hint``.
- Nimscript exports  a proc named ``patchFile`` which can be used to
  patch modules or include files for different Nimble packages, including
  the ``stdlib`` package.


Language Additions
------------------

- Added ``{.intdefine.}`` and ``{.strdefine.}`` macros to make use of
  (optional) compile time defines.
- If the first statement is an ``import system`` statement then ``system``
  is not imported implicitly anymore. This allows for code like
  ``import system except echo`` or ``from system import nil``.

Bugfixes
--------
