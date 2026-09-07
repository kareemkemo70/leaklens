# -*- coding: utf-8 -*-
"""
Zone mapping logic extracted from the training notebook.

Zone layout (SCADA sensor naming: nXX):
  Zone 1 — Early Network       : n1  – n30
  Zone 2 — Middle Sensors      : n31 – n60
  Zone 3 — Main Distribution   : n61 – n90
  Zone 4 — End Network / High Pressure : n91 – n120
  Zone 5 — Extended Network    : n121 – n300
"""

from collections import Counter
from typing import List


def get_zone(sensor_name: str) -> str:
    """Map a sensor name (e.g. 'n33', 'n33_x') to its zone string."""
    try:
        # Strip suffixes like _x, _y, _flow, etc.
        base = sensor_name.split("_")[0].lower().strip()
        # Remove leading 'n'
        idx = int(base.replace("n", ""))
    except (ValueError, AttributeError):
        return "Unknown"

    if 1 <= idx <= 30:
        return "Zone 1"
    elif 31 <= idx <= 60:
        return "Zone 2"
    elif 61 <= idx <= 90:
        return "Zone 3"
    elif 91 <= idx <= 120:
        return "Zone 4"
    elif 121 <= idx <= 300:
        return "Zone 5"
    else:
        return "Unknown"


def dominant_zone(sensors: List[str]) -> str:
    """Return the most common zone among a list of sensor names."""
    if not sensors:
        return "Unknown"
    zones = [get_zone(s) for s in sensors]
    return Counter(zones).most_common(1)[0][0]


ZONE_DESCRIPTIONS = {
    "Zone 1": "Early Network (Intake / Primary Pipes)",
    "Zone 2": "Middle Distribution Network",
    "Zone 3": "Main Distribution Grid",
    "Zone 4": "End Network / High Pressure Zones",
    "Zone 5": "Extended / Remote Network",
    "Unknown": "Unclassified Sensor",
}
