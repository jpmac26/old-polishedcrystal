const_value set 2

SoulHouseB3F_MapScriptHeader:
.MapTriggers:
	db 0

.MapCallbacks:
	db 0

SoulHouseB3F_MapEventHeader:
	; filler
	db 0, 0

.Warps:
	db 1
	warp_def $4, $3, 3, SOUL_HOUSE_B2F

.XYTriggers:
	db 0

.Signposts:
	db 0

.PersonEvents:
	db 0
