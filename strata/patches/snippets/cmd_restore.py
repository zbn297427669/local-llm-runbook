def _restore_gpu_power() -> None:
    """Put the graphics card's power limit back after a stop.

    A local addition (not upstream): this PC's USB display and keyboard dropped whenever the
    card jumped to full load, so the card is capped while the model serves. Stopping the model
    should undo that. When the driver wants administrator rights this asks for them through the
    normal Windows UAC prompt (see gpu_power.py); a card already at its default is left alone.
    """
    from strata_cli.launch import gpu_power
    if not gpu_power.available():
        return
    try:
        ok, defaults, asked = gpu_power.restore()
    except Exception:                                    # noqa: BLE001 - a stop must never fail on this
        return
    if not defaults:
        return                                           # nothing was capped
    if ok:
        note = " (Windows asked for administrator rights)" if asked else ""
        _say(f"Graphics card power limit restored to {defaults[0]} W{note}.")
    else:
        _say("[!] The graphics card is still capped.")
        _say("    Run this in an administrator terminal: nvidia-smi -pl 350")
