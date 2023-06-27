# dPIR
Set varying brightness at different times of day for CBus PIR triggered lights.

At sunrise the target level is set to high, then lowered at a specified evening time, then lowered again at a subsequent time or when a late night scene is set. When the optional 'scene' is set then the target level will be immediately set to super-low. The late night scene is triggered elsewhere (a key?).

If the group is manually set to off (or by a scene), then control of the group by this script will suspend for a given 'egress' to allow for area egress with the PIR disabled. This is useful for turning off the hall or toilet light when leaving and not having the PIR trigger again.

If the group is manually set to a level other than the script target (like with a switch timer) then this script will not turn it off after the timer runtime. To re-enable the timer function the group must be switched to off.

A PIR to turn on the group should be configured to pulse a lighting group (the 'trigger' group) for approx one second, and also have a lighting group (the 'enable' group) for that PIR defined.

There are two scripts:

- Dynamic PIR: Resident, zero delay
- DPIR: Event-based, on keyword "DPIR"

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

Defaults are as follows: defaultRun = '120', defaultLv = '210/127/127', defaultHr = '22/0', defaultRamp = '4/8', defaultDd = '15', defaultScene = ''.

Keyword examples, applied to each PIR trigger group:

- DPIR, grp=Hall Mid Pendants, en=Hall PIR_1 Enable, run=90, lv=127/89/31, hr=22/0, ramp=4/12, dd=15, scene=Late night, 
- DPIR, grp=Hutch Bathroom, en=Hutch Bathroom PIR Enable, run=300, lv=179/127, hr=22, ramp=0/12, dd=5, 
- DPIR, grp=Outside Carport, en=Outside Carport Enable, run=120, lv=205/153, hr=22, ramp=4/8, dd=15, 
- DPIR, grp=Kitchen Pantry LV, en=Kitchen Pantry PIR Enable, run=60, lv=240/180/80, hr=22/0, ramp=0/20, dd=0, 

Note: Changes to keywords are not detected (to improve performance), and require a resident script re-start, and the DPIR event-based script also needs to be re-started for newly added DPIR keywords (otherwise it will not fire for those new groups).