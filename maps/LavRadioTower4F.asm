const_value set 2

LavRadioTower4F_MapScriptHeader:
.MapTriggers:
	db 0

.MapCallbacks:
	db 0

LavRadioTower4F_MapEventHeader:
	; filler
	db 0, 0

.Warps:
	db 2
	warp_def $0, $f, 2, LAV_RADIO_TOWER_3F
	warp_def $0, $8, 1, LAV_RADIO_TOWER_5F

.XYTriggers:
	db 0

.Signposts:
	db 0

.PersonEvents:
	db 0
