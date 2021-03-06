const_value set 2
	const ROUTE1617GATE_OFFICER

Route1617Gate_MapScriptHeader:
.MapTriggers:
	db 1

	; triggers
	dw UnknownScript_0x733e9, 0

.MapCallbacks:
	db 0

UnknownScript_0x733e9:
	end

OfficerScript_0x733ea:
	jumptextfaceplayer UnknownText_0x73408

UnknownScript_0x733ed:
	checkitem BICYCLE
	iffalse UnknownScript_0x733f3
	end

UnknownScript_0x733f3:
	showemote EMOTE_SHOCK, ROUTE1617GATE_OFFICER, 15
	spriteface PLAYER, UP
	opentext
	writetext UnknownText_0x73496
	waitbutton
	closetext
	applymovement PLAYER, MovementData_0x73405
	end

MovementData_0x73405:
	step_right
	turn_head_left
	step_end

UnknownText_0x73408:
	text "Cycling Road"
	line "starts here."

	para "It's all downhill,"
	line "so it's totally"
	cont "exhilarating."

	para "It's a great sort"
	line "of feeling that"

	para "you can't get from"
	line "a ship or train."
	done

UnknownText_0x73496:
	text "Hey! Whoa! Stop!"

	para "You can't go out"
	line "on the Cycling"

	para "Road without a"
	line "Bicycle."
	done

Route1617Gate_MapEventHeader:
	; filler
	db 0, 0

.Warps:
	db 5
	warp_def $5, $0, 1, ROUTE_16_SOUTH
	warp_def $6, $0, 2, ROUTE_16_SOUTH
	warp_def $5, $9, 2, ROUTE_16_NORTH
	warp_def $6, $9, 3, ROUTE_16_NORTH
	warp_def $8, $8, 1, ROUTE_16_17_GATE_2F

.XYTriggers:
	db 5
	xy_trigger 0, $3, $5, $0, UnknownScript_0x733ed, $0, $0
	xy_trigger 0, $4, $5, $0, UnknownScript_0x733ed, $0, $0
	xy_trigger 0, $5, $5, $0, UnknownScript_0x733ed, $0, $0
	xy_trigger 0, $6, $5, $0, UnknownScript_0x733ed, $0, $0
	xy_trigger 0, $7, $5, $0, UnknownScript_0x733ed, $0, $0

.Signposts:
	db 0

.PersonEvents:
	db 1
	person_event SPRITE_OFFICER, 1, 5, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, (1 << 3) | PAL_OW_BLUE, PERSONTYPE_SCRIPT, 0, OfficerScript_0x733ea, -1
