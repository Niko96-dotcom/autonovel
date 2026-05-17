"""Command-line entrypoints for Autonovel."""

from __future__ import annotations

import argparse


def main():
    parser = argparse.ArgumentParser(prog="autonovel")
    sub = parser.add_subparsers(dest="command", required=True)
    ui = sub.add_parser("ui", help="Start the local web UI")
    ui.add_argument("--host", default="127.0.0.1")
    ui.add_argument("--port", type=int, default=8000)
    ui.add_argument("--reload", action="store_true")
    args = parser.parse_args()

    if args.command == "ui":
        import uvicorn

        uvicorn.run(
            "autonovel.server:app",
            host=args.host,
            port=args.port,
            reload=args.reload,
        )


if __name__ == "__main__":
    main()
