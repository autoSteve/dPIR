# dPIR
Dynamic PIR level (for the SHAC/NAC/AC2/NAC2)

These scripts set a light level when triggered by a PIR to differing set points throughout a day.

Two scripts:
- *Dynamic PIR*: Resident, zero sleep
- *DPIR*: Event-based, set to fire on the keyword 'DPIR'

At sunrise the target level is set to high, then lowered at a specified evening time, then lowered again at a subsequent time or when a late night scene is set. When the optional 'scene' is set then the target level will be immediately set to super-low. The late night scene is triggered elsewhere (a key?).

If the group is manually set to off (or by a scene), then control of the group by this script will suspend for a given 'egress' time (in seconds) to allow for area departure with the PIR disabled. This is useful for turning off the hall or toilet light when leaving and not having the PIR trigger immediately if in its sensing field.

If the group is manually set to a level other than the script target (like with a switch timer) then this script will not turn it off after the script timer runtime. To re-enable the script timer function the group must be switched to off.

A PIR to turn on the group must be configured to pulse a lighting group on motion (the 'trigger' group) for approx one second, and also have a lighting group set to enable the sensor (the 'enable' group).

Set keywords for the trigger group, which will be read by this script.
- DPIR
- grp= Group to control (mandatory)
- en= Enable group (mandatory)
- run= Runtime
- lv= Dynamic levels - 3x separated by slash = daytime/low/super-low (super-low optional)
- hr= Hour transitions - 2x sep by / = hour-for-low/hour-for-super-low (super-low optional)
- ramp= Ramp rate - 2x sep by / = ramp-on/ramp-off
- dd= Seconds to allow for egress (disable duration)
- scene= Name of a late night scene (when set make immediate switch to super-low dynamic level)

Defaults are set in the Dynamic PIR resident script.

Keyword examples, applied to each PIR trigger group:
- DPIR, grp=Hall Mid Pendants, en=Hall PIR_1 Enable, run=90, lv=127/89/31, hr=22/0, ramp=4/12, dd=15, scene=Late night, 
- DPIR, grp=Hutch Bathroom, en=Hutch Bathroom PIR Enable, run=300, lv=179/127, hr=22, ramp=0/12, dd=5, 
- DPIR, grp=Outside Carport, en=Outside Carport Enable, run=120, lv=205/153, hr=22, ramp=4/8, dd=15, 
- DPIR, grp=Kitchen Pantry LV, en=Kitchen Pantry PIR Enable, run=60, lv=240/180/80, hr=22/0, ramp=0/20, dd=0, 

Note: Changes to keywords are not detected (to improve performance), and require a resident script re-start. The DPIR event-based script also needs to be re-started for newly added DPIR keywords (otherwise it will not fire for those new groups).