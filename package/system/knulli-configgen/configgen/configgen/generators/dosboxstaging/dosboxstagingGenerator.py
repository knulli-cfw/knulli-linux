from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

from ... import Command
from ...batoceraPaths import CONFIGS
from ..Generator import Generator

if TYPE_CHECKING:
    from ...types import HotkeysContext


# DOS game folders come with whatever casing the original archive had, so the
# support files are matched case-insensitively rather than by exact name.
def _find_iname(directory: Path, filename: str) -> Path | None:
    if not directory.is_dir():
        return None

    lower_filename = filename.lower()
    return next((f for f in directory.iterdir()
                 if f.is_file() and f.name.lower() == lower_filename), None)


class DosBoxStagingGenerator(Generator):

    # Main entry of the module
    # Return command
    def generate(self, system, rom, playersControllers, metadata, guns, wheels, gameResolution):
        # Find rom path, handling a rom that is a single file rather than a folder
        gameDir = Path(rom)
        if not gameDir.is_dir():
            gameDir = gameDir.parent

        resourceDir = CONFIGS / 'dosbox'
        resourceConf = _find_iname(resourceDir, "dosbox-staging.conf")

        gameCfg = _find_iname(gameDir, "dosbox.cfg")
        gameConf = _find_iname(gameDir, "dosbox.conf")
        gameBat = _find_iname(gameDir, "dosbox.bat")

        commandArray: list[str | Path] = [
            '/usr/bin/dosbox-staging',
            "--fullscreen",
            "-userconf",
            "--working-dir", str(gameDir),
            # ROOT is the name knulli has always exported, WORKDIR the one the
            # shared resource scripts expect.  Both name the game folder.
            "-c", f"""set ROOT={gameDir!s}""",
            "-c", f"""set WORKDIR={gameDir!s}""",
        ]

        if resourceDir.is_dir():
            commandArray.extend(["-c", f"""set RESDIR={resourceDir!s}"""])

        if resourceConf:
            commandArray.extend(["-c", f"""set RESCONF={resourceConf!s}"""])

        # --conf is relative to --working-dir, so the bare name is enough
        if gameCfg:
            commandArray.extend(["--conf", gameCfg.name, "-c", f"set GAMECFG={gameCfg.name}"])
        elif gameConf:
            commandArray.extend(["--conf", gameConf.name, "-c", f"set GAMECONF={gameConf.name}"])

        if gameBat:
            commandArray.extend([gameBat.name, "-c", f"set GAMEBAT={gameBat.name}"])

        if gameCfg or gameConf or gameBat:
            # The game brings its own setup, so skip the banner and quit the
            # emulator once it is done.
            commandArray.extend(["--set", "startup_verbosity=quiet", "--exit"])
        else:
            # Nothing to launch: leave the user at a C:\ prompt in the game
            # folder rather than exiting on a dosbox.bat that is not there.
            commandArray.extend(["-c", "@echo off", "-c", "mount c .", "-c", "c:"])

        return Command.Command(array=commandArray)

    def writesToRom(self, config) -> bool:
        return True

    def getHotkeysContext(self) -> HotkeysContext:
        return {
            "name": "dosboxstaging",
            "keys": { "exit": ["KEY_LEFTCTRL", "KEY_F9"] }
        }
