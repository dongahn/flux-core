###############################################################
# Copyright 2020 Lawrence Livermore National Security, LLC
# (c.f. AUTHORS, NOTICE.LLNS, COPYING)
#
# This file is part of the Flux resource manager framework.
# For details, see https://github.com/flux-framework.
#
# SPDX-License-Identifier: LGPL-3.0
###############################################################

import numbers
import collections
from _flux._idset import ffi, lib
from flux.wrapper import Wrapper, WrapperPimpl

IDSET_INVALID_ID = lib.IDSET_INVALID_ID
IDSET_FLAG_RANGE = lib.IDSET_FLAG_RANGE
IDSET_FLAG_BRACKETS = lib.IDSET_FLAG_BRACKETS


class IDsetIterator:
    def __init__(self, idset):
        self._idset = idset
        self._next = idset.pimpl.first()

    def __iter__(self):
        return self

    def __next__(self):
        result = self._next
        self._next = self._idset.pimpl.next(result)
        if result == IDSET_INVALID_ID:
            raise StopIteration
        return result


class IDset(WrapperPimpl):
    """A Flux idset object

    The IDset class wraps libflux-idset, and encapsulates a set of
    unordered non-negative integers. See idset_create(3).

    A Python IDset object may be created from a valid RFC22 idset string,
    e.g. "0", "0-3", "0,5,7", or any Python iterable type as long as the
    iterable contains only non-negative integers. For example:

    >>> ids = IDset("0-3")
    >>> ids2 = IDset([0, 1, 2, 3])
    >>> ids3 = IDset({0, 1, 2, 3})

    """

    class InnerWrapper(Wrapper):
        def __init__(
            self,
            arg="",
            handle=None,
        ):
            if handle is None:
                handle = lib.idset_decode(arg.encode("utf-8"))
                if handle == ffi.NULL:
                    raise ValueError(f"IDset(): Invalid argument: {arg}")
            super().__init__(
                ffi,
                lib,
                match=ffi.typeof("struct idset *"),
                prefixes=["idset_", "IDSET_"],
                destructor=lib.idset_destroy,
                handle=handle,
            )

    def __init__(self, arg="", flags=IDSET_FLAG_RANGE, handle=None):
        super().__init__()
        if isinstance(arg, collections.Iterable) and not isinstance(arg, str):
            self.pimpl = self.InnerWrapper()
            self.add(arg)
        else:
            self.pimpl = self.InnerWrapper(arg=arg, handle=handle)
        self.default_flags = flags

    def __str__(self):
        return self.encode()

    def __repr__(self):
        # Always encode repr with ranges
        ids = self.encode(flags=IDSET_FLAG_RANGE)
        return f"IDset('{ids}')"

    def __len__(self):
        return self.pimpl.count()

    def __iter__(self):
        return IDsetIterator(self)

    def __contains__(self, i):
        return self.test(i)

    def __getitem__(self, i):
        return self.test(i)

    def __setitem__(self, i, value):
        if value in (0, 1):
            value = bool(value)
        if not isinstance(value, bool):
            typestr = type(value)
            raise TypeError(f"IDset setitem must be bool or 0,1 not {typestr}")
        if value:
            self.set(i)
        else:
            self.clear(i)

    def __eq__(self, idset):
        return self.equal(idset)

    def equal(self, idset):
        if not isinstance(idset, IDset):
            raise TypeError
        return self.pimpl.equal(idset)

    def set_flags(self, flags):
        """Set default flags for IDset encoding:
        valid flags are IDSET_FLAG_RANGE and IDSET_FLAG_BRACKETS
        """
        self.default_flags = flags

    @staticmethod
    def _check_index(i, name):
        if not isinstance(i, numbers.Integral):
            typestr = type(i)
            raise TypeError(f"IDset.{name} supports integers, not {typestr}")
        if i < 0:
            raise ValueError(f"negative index passed to IDset.{name}")

    def test(self, i):
        """Test if an id is set in an IDset
        :param: i: the id to test
        """
        self._check_index(i, "test")
        return self.pimpl.test(i)

    def set(self, start, end=None):
        """Set an id or range of ids in an IDset
        :param: start: The first id to set
        :param: end: (optional) The last id in a range to set

        Returns a copy of self so that this will work:
        >>> print(IDset().set(0,3))

        """
        self._check_index(start, "set")
        if end is None:
            self.pimpl.set(start)
        else:
            self._check_index(end, "set")
            if end < start:
                raise ValueError(f"can't set range with {start} > {end}")
            self.pimpl.range_set(start, end)
        return self

    def clear(self, start, end=None):
        """Clear an id or range of ids in an IDset
        :param: start: The first id to clear
        :param: end: (optional) The last id in a range to clear

        Returns a copy of self so that this will work:
        >>> print(IDset("0-9").clear(0,3))

        """
        self._check_index(start, "clear")
        if end is None:
            self.pimpl.clear(start)
        else:
            self._check_index(end, "clear")
            if end < start:
                raise ValueError(f"can't set range with {start} > {end}")
            self.pimpl.range_clear(start, end)
        return self

    def expand(self):
        """Expand an IDset into a list of integers"""
        return list(self)

    def count(self):
        """Return the number of integers in an IDset"""
        return self.pimpl.count()

    def copy(self):
        return IDset(handle=self.pimpl.copy())

    def encode(self, flags=None):
        """Encode an IDset to a string.
        :param: flags: (optional) flags to influence encoding
        """
        if flags is None:
            flags = self.default_flags
        #
        #  N.B. Do not use automatic wrapper call here to avoid leaking
        #  `char *` result. Instead, explicitly call free() after copying
        #  the returned string to Python
        #
        val = lib.idset_encode(self.handle, flags)
        result = ffi.string(val)
        lib.free(val)
        return result.decode("utf-8")

    def first(self):
        """Return the first id set in an IDset"""
        return self.pimpl.first()

    def next(self, i):
        """Return the next id set in an IDset after value i"""
        self._check_index(i, "next")
        return self.pimpl.next(i)

    def last(self):
        """Return the greatest id set in an IDset"""
        return self.pimpl.last()

    @staticmethod
    def arg_to_set(arg, method):
        if isinstance(arg, str):
            try:
                arg = IDset(arg)
            except:
                raise ValueError(f"IDset.{method}(): string isn't a valid idset")
        elif not isinstance(arg, collections.Iterable):
            typestr = type(arg)
            method = f"IDset.{method}()"
            raise TypeError(
                f"{method}: expected an idset string or iterable, got {typestr}"
            )
        return set(arg)

    def add(self, arg):
        """Add all ids or values in arg to IDset
        :param: arg: IDset, string, or iterable of integers to add
        """
        for i in self.arg_to_set(arg, "add"):
            self.set(i)
        return self

    def subtract(self, arg):
        """subtract all ids or values in arg from IDset
        :param: arg: IDset, string, or iterable of integers to subtract
        """
        for i in self.arg_to_set(arg, "subtract"):
            self.clear(i)
        return self

    def union(self, *args):
        """Return the union of the current IDset and all args

        All args will be converted to IDsets if possible, i.e. any IDset,
        valid idset string, or iterable composed of integers will work.
        """
        result = set(self)
        for idset in args:
            if not isinstance(idset, IDset):
                idset = IDset(idset)
            result = result | set(idset)
        return IDset(result)

    def intersect(self, *args):
        """Return the set intersection of the target IDset and all args

        All args will be converted to IDsets if possible, i.e. any IDset,
        valid idset string, or iterable composed of integers will work.
        """
        result = set(self)
        for idset in args:
            if not isinstance(idset, IDset):
                idset = IDset(idset)
            result = result & set(idset)
        return IDset(result)


def decode(string):
    """Decode an idset string and return IDset object"""
    return IDset(string)
