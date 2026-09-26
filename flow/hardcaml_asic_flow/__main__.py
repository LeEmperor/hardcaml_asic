"""`python -m hardcaml_asic_flow`; the installed launcher calls `cli.main`."""

import sys

from .cli import main


if __name__ == "__main__":
    sys.exit(main())
