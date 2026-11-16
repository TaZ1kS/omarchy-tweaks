#!/usr/bin/env bash
# Ensure the fixed HEADLESS-1 phone screen exists with the correct
# size (1200x540) and position (centered under the central monitor).
#
# All the logic lives in phone-screen — this just keeps the output ready
# on login without starting wayvnc.
exec ${HOME}/.local/bin/phone-screen ensure
