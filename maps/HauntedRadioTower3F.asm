const_value set 2

HauntedRadioTower3F_MapScriptHeader:
.MapTriggers:
	db 0

.MapCallbacks:
	db 0

HauntedRadioTower3F_MapEventHeader:
	; filler
	db 0, 0

.Warps:
	db 2
	warp_def $0, $2, 2, HAUNTED_RADIO_TOWER_2F
	warp_def $0, $f, 1, HAUNTED_RADIO_TOWER_4F

.XYTriggers:
	db 0

.Signposts:
	db 0

.PersonEvents:
	db 0
