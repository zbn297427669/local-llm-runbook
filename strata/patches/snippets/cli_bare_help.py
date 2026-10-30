_HELP_COMMANDS = (
    # (command, what it does, the day-to-day ones first)
    ("launch", "start or stop a model, and watch it"),
    ("connect", "print the setup for a coding app on the running server"),
    ("status", "one snapshot of what is running"),
    ("monitor", "the terminal monitor (seven views)"),
    ("logs", "recent request activity"),
    ("models", "the installed model run configs"),
    ("update", "fetch the engine and components for this PC"),
    ("--version", "the version and the interpreter this runs on"),
)


def _print_bare_help(ap) -> None:
    """`strata` with no command: say what this is and the few commands people actually type.

    argparse's own "the following arguments are required: command" tells a newcomer nothing
    about which command to reach for, and the full list is 20 long. This is a local addition.
    """
    out = sys.stdout
    out.write("Strata - run a model on this computer, and point coding tools at it.\n")
    out.write("\n")
    out.write("Common commands:\n")
    width = max(len(c) for c, _ in _HELP_COMMANDS)
    for cmd, what in _HELP_COMMANDS:
        out.write(f"  strata {cmd:<{width}}  {what}\n")
    out.write("\n")
    out.write("Every command:\n")
    # the parser's own list, so this never goes stale when a command is added
    names = []
    for action in ap._actions:
        if isinstance(action, argparse._SubParsersAction):
            names = list(action.choices)
            break
    out.write("  " + "  ".join(names) + "\n")
    out.write("\n")
    out.write("  strata <command> --help     what a command does and its options\n")
    out.write("  strata launch --help        the long one; most flags live here\n")
    out.write("\n")
    out.flush()
