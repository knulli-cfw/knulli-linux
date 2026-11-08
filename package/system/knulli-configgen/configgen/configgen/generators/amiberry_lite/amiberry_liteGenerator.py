from __future__ import annotations

from typing import ClassVar

from ..amiberry.amiberryGenerator import AmiberryGenerator


class AmiberryLiteGenerator(AmiberryGenerator):
    """The SDL2 branch of amiberry.

    Same emulator and the same command line, installed under its own name, so
    everything here is a matter of where it lives.  It keeps its own config
    directory too: the two builds do not share a config format across a major
    version gap.
    """

    _NAME: ClassVar[str] = 'amiberry-lite'
    _BINARY: ClassVar[str] = '/usr/bin/amiberry-lite'
    _SHARE: ClassVar[str] = '/usr/share/amiberry-lite'
    _CONF_FILE: ClassVar[str] = 'amiberry-lite.conf'
