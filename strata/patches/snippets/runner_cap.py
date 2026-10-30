    def _cap_gpu_power(self) -> None:
        """Hold the graphics card's power limit down while this model serves.

        A local addition (not upstream). On this PC the USB display and keyboard dropped every
        time the card stepped from idle to full load, so the card is capped for the duration of
        the service; `strata launch --stop` puts it back (see strata_cli/launch/cmd.py).

        The limit comes from STRATA_GPU_POWER_LIMIT (watts). Unset or 0 leaves the card alone,
        so a machine without the problem is unaffected. Setting it needs administrator rights:
        without them nvidia-smi refuses and one line says so, then the launch carries on.
        """
        raw = os.environ.get("STRATA_GPU_POWER_LIMIT", "").strip()
        if not raw:
            return
        try:
            want = int(float(raw))
        except ValueError:
            self.emit("start", f"STRATA_GPU_POWER_LIMIT={raw!r} is not a number of watts; the card is left alone.",
                      100, level="warn")
            return
        if want <= 0:
            return
        from strata_cli.launch import gpu_power
        if not gpu_power.available():
            return
        ok, why, asked = gpu_power.cap(want)
        if ok:
            note = " (Windows asked for administrator rights)" if asked else ""
            self.emit("start", f"Graphics card capped at {want} W for this run, restored on --stop{note}.")
        elif asked:
            self.emit("start", f"The graphics card was not capped at {want} W: {why}; serving uncapped.",
                      100, level="warn")
        else:
            self.emit("start", f"The graphics card could not be capped at {want} W ({why}); serving uncapped.",
                      100, level="warn")
