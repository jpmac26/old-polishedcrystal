DoPlayerTurn: ; 34000
	call SetPlayerTurn

	ld a, [wPlayerAction]
	and a
	ret nz

	ld a, [BattleType]
	cp BATTLETYPE_GHOST
	jr nz, DoTurn

	ld hl, ScaredText
	call StdBattleTextBox
	ret

; 3400a


DoEnemyTurn: ; 3400a
	call SetEnemyTurn

	ld a, [BattleType]
	cp BATTLETYPE_GHOST
	jr nz, .not_ghost

	ld hl, GetOutText
	call StdBattleTextBox
	ret

.not_ghost
	ld a, [wLinkMode]
	and a
	jr z, DoTurn

	ld a, [wBattleAction]
	cp BATTLEACTION_STRUGGLE
	jr z, DoTurn
	cp BATTLEACTION_SWITCH1
	ret nc

	; fallthrough
; 3401d


DoTurn: ; 3401d
; Read in and execute the user's move effects for this turn.

	xor a
	ld [wTurnEnded], a

	; Effect command checkturn is called for every move.
	call CheckTurn

	ld a, [wTurnEnded]
	and a
	ret nz

	call UpdateMoveData
; 3402c


DoMove: ; 3402c
; Get the user's move effect.
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	ld c, a
	ld b, 0
	ld hl, MoveEffectsPointers
	add hl, bc
	add hl, bc
	ld a, BANK(MoveEffectsPointers)
	call GetFarHalfword

	ld de, BattleScriptBuffer

.GetMoveEffect:
	ld a, BANK(MoveEffects)
	call GetFarByte
	inc hl
	ld [de], a
	inc de
	cp $ff
	jr nz, .GetMoveEffect

; Start at the first command.
	ld hl, BattleScriptBuffer
	ld a, l
	ld [BattleScriptBufferLoc], a
	ld a, h
	ld [BattleScriptBufferLoc + 1], a

.ReadMoveEffectCommand:

; ld a, [BattleScriptBufferLoc++]
	ld a, [BattleScriptBufferLoc]
	ld l, a
	ld a, [BattleScriptBufferLoc + 1]
	ld h, a

	ld a, [hli]

	push af
	ld a, l
	ld [BattleScriptBufferLoc], a
	ld a, h
	ld [BattleScriptBufferLoc + 1], a
	pop af

; endturn_command (-2) is used to terminate branches without ending the read cycle.
	cp endturn_command
	ret nc

; The rest of the commands (01-af) are read from BattleCommandPointers.
	push bc
	dec a
	ld c, a
	ld b, 0
	ld hl, BattleCommandPointers
	add hl, bc
	add hl, bc
	pop bc

	ld a, BANK(BattleCommandPointers)
	call GetFarHalfword

	call .DoMoveEffectCommand

	jr .ReadMoveEffectCommand

.DoMoveEffectCommand:
	jp hl

; 34084


CheckTurn:
BattleCommand_CheckTurn: ; 34084
; checkturn

; Repurposed as hardcoded turn handling. Useless as a command.

	xor a
	ld [AttackMissed], a
	ld [EffectFailed], a
	ld [wKickCounter], a
	ld [AlreadyDisobeyed], a
	ld [AlreadyFailed], a
	ld [wSomeoneIsRampaging], a

	ld a, $10 ; 1.0
	ld [TypeModifier], a

	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	bit SUBSTATUS_RECHARGE, [hl]
	jr z, .no_recharge

	res SUBSTATUS_RECHARGE, [hl]
	ld hl, MustRechargeText
	call StdBattleTextBox
	call CantMove
	jp EndTurn

.no_recharge
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	bit SUBSTATUS_FLINCHED, [hl]
	jr z, .not_flinched

	res SUBSTATUS_FLINCHED, [hl]
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp INNER_FOCUS
	jr z, .not_flinched
	push af
	ld hl, FlinchedText
	call StdBattleTextBox
	pop af
	cp STEADFAST
	jr nz, .skip_steadfast
	farcall SteadfastAbility

.skip_steadfast
	call CantMove
	jp EndTurn

.not_flinched
	ld a, BATTLE_VARS_STATUS
	call GetBattleVarAddr
	ld a, [hl]
	and SLP
	jr z, .not_asleep

	dec a
	ld [hl], a
	and a ; check if the sleep timer ran out
	jr z, .woke_up

	; Early Bird decreases the sleep timer twice as fast (including Rest).
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp EARLY_BIRD
	jr nz, .no_early_bird
	; duplicated, but too few lines to make merging it worth it
	ld a, [hl]
	dec a
	ld [hl], a
	and a ; check if the sleep timer ran out
	jr z, .woke_up

.no_early_bird
	xor a
	ld [wNumHits], a
	ld de, ANIM_SLP
	call FarPlayBattleAnimation
	jr .fast_asleep

.woke_up
	ld hl, WokeUpText
	call StdBattleTextBox
	call CantMove
	ld a, [hBattleTurn]
	and a
	jr nz, .enemy1
	call UpdateBattleMonInParty
	ld hl, UpdatePlayerHUD
	jr .ok1
.enemy1
	call UpdateEnemyMonInParty
	ld hl, UpdateEnemyHUD
.ok1
	call CallBattleCore
	ld a, $1
	ld [hBGMapMode], a
	jr .not_asleep

.fast_asleep
	ld hl, FastAsleepText
	call StdBattleTextBox

	; Sleep Talk bypasses sleep.
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	cp SLEEP_TALK
	jr z, .not_asleep

	call CantMove
	jp EndTurn

.not_asleep
	ld a, BATTLE_VARS_STATUS
	call GetBattleVarAddr
	bit FRZ, [hl]
	jr z, .not_frozen

	; Flame Wheel, Sacred Fire, Scald, and Flare Blitz thaw the user.
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	cp FLAME_WHEEL
	jr z, .thaw
	cp SACRED_FIRE
	jr z, .thaw
	cp SCALD
	jr z, .thaw
	cp FLARE_BLITZ
	jr z, .thaw

	; Check for defrosting
	call BattleRandom
	cp 1 + (20 percent)
	jr c, .thaw
	ld hl, FrozenSolidText
	call StdBattleTextBox
	xor a
	ld [wNumHits], a
	ld de, ANIM_FRZ
	call FarPlayBattleAnimation

	call CantMove
	jp EndTurn

.thaw
	call BattleCommand_Defrost

.not_frozen
	ld a, [hBattleTurn]
	and a
	jr nz, .enemy3
	ld hl, PlayerDisableCount
	jr .ok3
.enemy3
	ld hl, EnemyDisableCount
.ok3
	ld a, [hl]
	and a
	jr z, .not_disabled

	dec a
	ld [hl], a
	and $f
	jr nz, .not_disabled

	ld [hl], a
	ld a, [hBattleTurn]
	and a
	jr nz, .enemy4
	ld [DisabledMove], a
	jr .ok4
.enemy4
	ld [EnemyDisabledMove], a
.ok4
	ld hl, DisabledNoMoreText
	call StdBattleTextBox

.not_disabled
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVar
	add a ; bit SUBSTATUS_CONFUSED, a
	jr nc, .not_confused
	ld a, [hBattleTurn]
	and a
	jr nz, .enemy5
	ld hl, PlayerConfuseCount
	jr .ok5
.enemy5
	ld hl, EnemyConfuseCount
.ok5
	dec [hl]
	jr nz, .confused

	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	res SUBSTATUS_CONFUSED, [hl]
	ld hl, ConfusedNoMoreText
	call StdBattleTextBox
	jr .not_confused

.confused
	ld hl, IsConfusedText
	call StdBattleTextBox
	xor a
	ld [wNumHits], a
	ld de, ANIM_CONFUSED
	call FarPlayBattleAnimation

	; 33% chance of hitting itself (updated from 50% in Gen VII)
	call BattleRandom
	cp 1 + (33 percent)
	jr nc, .not_confused

	; clear confusion-dependent substatus
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	ld a, [hl]
	and 1 << SUBSTATUS_CONFUSED
	ld [hl], a

	call HitConfusion
	call CantMove
	jp EndTurn

.not_confused
	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVar
	add a ; bit SUBSTATUS_ATTRACT
	jr nc, .not_infatuated

	ld hl, InLoveWithText
	call StdBattleTextBox
	xor a
	ld [wNumHits], a
	ld de, ANIM_IN_LOVE
	call FarPlayBattleAnimation

	; 50% chance of infatuation
	call BattleRandom
	cp 1 + (50 percent)
	jr c, .not_infatuated

	ld hl, InfatuationText
	call StdBattleTextBox
	call CantMove
	jp EndTurn

.not_infatuated


	; Are we using a disabled move?
	ld a, [hBattleTurn]
	and a
	jr nz, .enemy6
	ld a, [DisabledMove]
	ld hl, CurPlayerMove
	jr .ok6
.enemy6
	ld a, [EnemyDisabledMove]
	ld hl, CurEnemyMove
.ok6
	and a
	jr z, .no_disabled_move ; can't disable a move that doesn't exist
	cp [hl]
	jr nz, .no_disabled_move

	call MoveDisabled
	call CantMove
	jp EndTurn

.no_disabled_move
	ld a, BATTLE_VARS_STATUS
	call GetBattleVarAddr
	bit PAR, [hl]
	ret z

	; 25% chance to be fully paralyzed
	call BattleRandom
	cp 1 + (25 percent)
	ret nc

	ld hl, FullyParalyzedText
	call StdBattleTextBox
	xor a
	ld [wNumHits], a
	ld de, ANIM_PAR
	call FarPlayBattleAnimation
	call CantMove
	; fallthrough


EndTurn:
	ld a, $1
	ld [wTurnEnded], a
	jp ResetDamage


CantMove: ; 341f0
	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	res SUBSTATUS_ROLLOUT, [hl]

	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	ld a, [hl]
	and $ff ^ (1<<SUBSTATUS_RAMPAGE + 1<<SUBSTATUS_CHARGED)
	ld [hl], a

	call ResetFuryCutterCount

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	cp FLY
	jr z, .fly_dig

	cp DIG
	ret nz

.fly_dig
	res SUBSTATUS_UNDERGROUND, [hl]
	res SUBSTATUS_FLYING, [hl]
	jp AppearUserRaiseSub

; 34216



OpponentCantMove: ; 34216
	call SwitchTurn
	call CantMove
	jp SwitchTurn

; 3421f


MoveDisabled: ; 3438d

	; Make sure any charged moves fail
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	res SUBSTATUS_CHARGED, [hl]

	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	ld [wNamedObjectIndexBuffer], a
	call GetMoveName

	ld hl, DisabledMoveText
	jp StdBattleTextBox

; 343a5


HitConfusion: ; 343a5

	ld hl, HurtItselfText
	call StdBattleTextBox

	xor a
	ld [CriticalHit], a

	call HitSelfInConfusion
	call BattleCommand_DamageCalc
	call BattleCommand_LowerSub

	xor a
	ld [wNumHits], a

	; Flicker the monster pic unless flying or underground.
	ld de, ANIM_HIT_CONFUSION
	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVar
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	call z, PlayFXAnimID

	ld a, [hBattleTurn]
	and a
	jr nz, .enemy
	ld hl, UpdatePlayerHUD
	call CallBattleCore
	ld a, $1
	ld [hBGMapMode], a
	ld c, $1
	call PlayerHurtItself
	jp BattleCommand_RaiseSub
.enemy
	ld c, $1
	call EnemyHurtItself
	jp BattleCommand_RaiseSub

; 343db


BattleCommand_CheckObedience: ; 343db
; checkobedience

	; Enemy can't disobey
	ld a, [hBattleTurn]
	and a
	ret nz

	call CheckUserIsCharging
	ret nz

	; If we've already checked this turn
	ld a, [AlreadyDisobeyed]
	and a
	ret nz

	xor a
	ld [AlreadyDisobeyed], a

	; No obedience in link battles
	; (since no handling exists for enemy)
	ld a, [wLinkMode]
	and a
	ret nz

	ld a, [InBattleTowerBattle]
	and a
	ret nz

	; If the monster's id doesn't match the player's,
	; some conditions need to be met.
	ld a, MON_ID
	call BattlePartyAttr

	ld a, [PlayerID]
	cp [hl]
	jr nz, .obeylevel
	inc hl
	ld a, [PlayerID + 1]
	cp [hl]
	ret z
	ld a, [InitialOptions]
	bit TRADED_BEHAVIOR, a
	ret z


.obeylevel
	; The maximum obedience level is constrained by owned badges:
	ld hl, JohtoBadges

	; risingbadge
	bit RISINGBADGE, [hl]
	ld a, MAX_LEVEL + 1
	jr nz, .getlevel

	; mineralbadge
	bit MINERALBADGE, [hl]
	ld a, 70
	jr nz, .getlevel

	; fogbadge
	bit FOGBADGE, [hl]
	ld a, 50
	jr nz, .getlevel

	; hivebadge
	bit HIVEBADGE, [hl]
	ld a, 30
	jr nz, .getlevel

	; zephyrbadge
	bit ZEPHYRBADGE, [hl]
	ld a, 20
	jr nz, .getlevel

	; no badges
	ld a, 10


.getlevel
; c = obedience level
; d = monster level
; b = c + d

	ld b, a
	ld c, a

	ld a, [BattleMonLevel]
	ld d, a

	add b
	ld b, a

; No overflow (this should never happen)
	jr nc, .checklevel
	ld b, $ff


.checklevel
; If the monster's level is lower than the obedience level, it will obey.
	ld a, c
	cp d
	ret nc


; Random number from 0 to obedience level + monster level
.rand1
	call BattleRandom
	swap a
	cp b
	jr nc, .rand1

; The higher above the obedience level the monster is,
; the more likely it is to disobey.
	cp c
	ret c

; Sleep-only moves have separate handling, and a higher chance of
; being ignored. Lazy monsters like their sleep.
	call IgnoreSleepOnly
	ret c


; Another random number from 0 to obedience level + monster level
.rand2
	call BattleRandom
	cp b
	jr nc, .rand2

; A second chance.
	cp c
	jr c, .UseInstead


; No hope of using a move now.

; b = number of levels the monster is above the obedience level
	ld a, d
	sub c
	ld b, a

; The chance of napping is the difference out of 256.
	call BattleRandom
	swap a
	sub b
	jr c, .Nap

; The chance of not hitting itself is the same.
	cp b
	jr nc, .DoNothing

	ld hl, WontObeyText
	call StdBattleTextBox
	call HitConfusion
	jp .EndDisobedience


.Nap:
	call BattleRandom
	add a
	swap a
	and SLP
	jr z, .Nap

	ld [BattleMonStatus], a

	ld hl, BeganToNapText
	jr .Print


.DoNothing:
	call BattleRandom
	and %11

	ld hl, LoafingAroundText
	and a
	jr z, .Print

	ld hl, WontObeyText
	dec a
	jr z, .Print

	ld hl, TurnedAwayText
	dec a
	jr z, .Print

	ld hl, IgnoredOrdersText

.Print:
	call StdBattleTextBox
	jp .EndDisobedience


.UseInstead:

; Can't use another move if the monster only has one!
	ld a, [BattleMonMoves + 1]
	and a
	jr z, .DoNothing

; Don't bother trying to handle Disable.
	ld a, [DisabledMove]
	and a
	jr nz, .DoNothing


	ld hl, BattleMonPP
	ld de, BattleMonMoves
	ld b, 0
	ld c, NUM_MOVES

.GetTotalPP:
	ld a, [hli]
	and $3f ; exclude pp up
	add b
	ld b, a

	dec c
	jr z, .CheckMovePP

; Stop at undefined moves.
	inc de
	ld a, [de]
	and a
	jr nz, .GetTotalPP


.CheckMovePP:
	ld hl, BattleMonPP
	ld a, [CurMoveNum]
	ld e, a
	ld d, 0
	add hl, de

; Can't use another move if only one move has PP.
	ld a, [hl]
	and $3f
	cp b
	jr z, .DoNothing


; Make sure we can actually use the move once we get there.
	ld a, 1
	ld [AlreadyDisobeyed], a

	ld a, [w2DMenuNumRows]
	ld b, a

; Save the move we originally picked for afterward.
	ld a, [CurMoveNum]
	ld c, a
	push af


.RandomMove:
	call BattleRandom
	and %11 ; NUM_MOVES - 1

	cp b
	jr nc, .RandomMove

; Not the move we were trying to use.
	cp c
	jr z, .RandomMove

; Make sure it has PP.
	ld [CurMoveNum], a
	ld hl, BattleMonPP
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	and $3f
	jr z, .RandomMove


; Use it.
	ld a, [CurMoveNum]
	ld c, a
	ld b, 0
	ld hl, BattleMonMoves
	add hl, bc
	ld a, [hl]
	ld [CurPlayerMove], a

	call SetPlayerTurn
	call UpdateMoveData
	call DoMove


; Restore original move choice.
	pop af
	ld [CurMoveNum], a


.EndDisobedience:
	xor a
	ld [LastPlayerMove], a
	ld [LastEnemyCounterMove], a

	; Break Encore too.
	ld hl, PlayerSubStatus2
	res SUBSTATUS_ENCORED, [hl]
	xor a
	ld [PlayerEncoreCount], a

	jp EndMoveEffect

; 3451f


IgnoreSleepOnly: ; 3451f

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar

	cp SLEEP_TALK
	jr z, .CheckSleep
	and a
	ret

.CheckSleep:
	ld a, BATTLE_VARS_STATUS
	call GetBattleVar
	and SLP
	ret z

; 'ignored orders…sleeping!'
	ld hl, IgnoredSleepingText
	call StdBattleTextBox

	call EndMoveEffect

	scf
	ret

; 34541


BattleCommand_UsedMoveText: ; 34541
; usedmovetext
	farcall DisplayUsedMoveText
	ret

; 34548


CheckUserIsCharging: ; 34548

	ld a, [hBattleTurn]
	and a
	ld a, [wPlayerCharging] ; player
	jr z, .end
	ld a, [wEnemyCharging] ; enemy
.end
	and a
	ret

; 34555


BattleCommand_DoTurn: ; 34555
	call CheckUserIsCharging
	ret nz

	ld hl, BattleMonPP
	ld de, PlayerSubStatus3
	ld bc, PlayerTurnsTaken

	ld a, [hBattleTurn]
	and a
	jr z, .proceed

	ld hl, EnemyMonPP
	ld de, EnemySubStatus3
	ld bc, EnemyTurnsTaken

.proceed

; If we've gotten this far, this counts as a turn.
	ld a, [bc]
	inc a
	ld [bc], a

	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	cp STRUGGLE
	ret z

	ld a, [de]
	and 1 << SUBSTATUS_IN_LOOP | 1 << SUBSTATUS_RAMPAGE
	ret nz

	call .consume_pp
	ld a, b
	and a
	jp nz, EndMoveEffect

	; SubStatus2
	inc de
	inc de

	ld a, [de]
	bit SUBSTATUS_TRANSFORMED, a
	ret nz

	ld a, [hBattleTurn]
	and a

	ld hl, PartyMon1PP
	ld a, [CurBattleMon]
	jr z, .player

; mimic this part entirely if wildbattle
	ld a, [wBattleMode]
	dec a
	jr z, .wild

	ld hl, OTPartyMon1PP
	ld a, [CurOTMon]

.player
	call GetPartyLocation

.consume_pp
	ld a, [hBattleTurn]
	and a
	ld a, [CurMoveNum]
	jr z, .okay
	ld a, [CurEnemyMoveNum]

.okay
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	and $3f
	jr z, .out_of_pp
	dec [hl]
	ld a, [hl]
	and $3f
	jr z, .take_one_pp_only
	ld a, BATTLE_VARS_ABILITY_OPP
	call GetBattleVar
	cp PRESSURE
	jr nz, .take_one_pp_only
	dec [hl]
.take_one_pp_only
	ld b, 0
	ret

.wild
	ld hl, wWildMonPP
	call .consume_pp
	ret

.out_of_pp
	call BattleCommand_MoveDelay
; get move effect
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
; continuous?
	ld hl, .continuousmoves
	ld de, 1
	call IsInArray

; 'has no pp left for [move]'
	ld hl, HasNoPPLeftText
	jr c, .print
; 'but no pp is left for the move'
	ld hl, NoPPLeftText
.print
	call StdBattleTextBox
	ld b, 1
	ret

; 34602

.continuousmoves ; 34602
	db EFFECT_RAZOR_WIND
	db EFFECT_SKY_ATTACK
	db EFFECT_SKULL_BASH
	db EFFECT_SOLAR_BEAM
	db EFFECT_FLY
	db EFFECT_ROLLOUT
	db EFFECT_BIDE
	db EFFECT_RAMPAGE
	db $ff
; 3460b


BattleCommand_Critical: ; 34631
; critical

; Determine whether this attack's hit will be critical.

	xor a
	ld [CriticalHit], a

	ld a, BATTLE_VARS_MOVE_POWER
	call GetBattleVar
	and a
	ret z

	call GetOpponentAbilityAfterMoldBreaker
	cp BATTLE_ARMOR
	ret z
	cp SHELL_ARMOR
	ret z
	ld a, [hBattleTurn]
	and a
	jr nz, .EnemyTurn

	ld hl, BattleMonItem
	ld a, [BattleMonSpecies]
	jr .Item

.EnemyTurn:
	ld hl, EnemyMonItem
	ld a, [EnemyMonSpecies]

.Item:
	ld c, 0

	cp CHANSEY
	jr nz, .Farfetchd
	ld a, [hl]
	cp LUCKY_PUNCH
	jr nz, .FocusEnergy

; +2 critical level
	ld c, 2
	jr .FocusEnergy

.Farfetchd:
	cp FARFETCH_D
	jr nz, .FocusEnergy
	ld a, [hl]
	cp STICK
	jr nz, .FocusEnergy

; +2 critical level
	ld c, 2
	jr .FocusEnergy

.FocusEnergy:
	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVar
	bit SUBSTATUS_FOCUS_ENERGY, a
	jr z, .CheckCritical

; +2 critical level (TODO: this also affects Dire Hit)
	inc c
	inc c

.CheckCritical:
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld de, 1
	ld hl, .Criticals
	push bc
	call IsInArray
	pop bc
	jr nc, .ScopeLens

; +1 critical level
	inc c

.ScopeLens:
	push bc
	call GetUserItem
	ld a, b
	cp HELD_CRITICAL_UP ; Increased critical chance (Scope Lens and Razor Claw)
	pop bc
	jr nz, .Ability

; +1 critical level
	inc c

.Ability:
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp SUPER_LUCK
	jr nz, .Tally

; +1 critical level
	inc c

.Tally:
	; Check for c > 2 which always crits
	ld a, c
	cp 3
	jr nc, .guranteed_crit
	ld hl, .Chances
	ld b, 0
	add hl, bc
	call BattleRandom
	cp [hl]
	ret nc
.guranteed_crit
	ld a, 1
	ld [CriticalHit], a
	ret

.Criticals:
	db KARATE_CHOP, RAZOR_LEAF, CRABHAMMER, SLASH, AEROBLAST, CROSS_CHOP, SHADOW_CLAW, STONE_EDGE, $ff
.Chances:
	; 6.25% 12.5%  50%   100%
	db $10,  $20,  $80,  $ff
	;   0     1     2     3+
; 346b2


BattleCommand_TripleKick: ; 346b2
; triplekick

	ld a, [wKickCounter]
	ld b, a
	inc b
	ld hl, CurDamage + 1
	ld a, [hld]
	ld e, a
	ld a, [hli]
	ld d, a
.next_kick
	dec b
	ret z
	ld a, [hl]
	add e
	ld [hld], a
	ld a, [hl]
	adc d
	ld [hli], a

; No overflow.
	jr nc, .next_kick
	ld a, $ff
	ld [hld], a
	ld [hl], a
	ret

; 346cd


BattleCommand_KickCounter: ; 346cd
; kickcounter

	ld hl, wKickCounter
	inc [hl]
	ret

; 346d2


BattleCommand_Stab: ; 346d2
; STAB = Same Type Attack Bonus
; Also handles type matchups and fire/water in sun/rain
; Uses an one-byte var to finally use for damage calculation. Max/min listed in case
; future extension is done to keep potential overflow/rounding errors in mind.
; Min value: $02 (quad-resist, no STAB, bad weather modifier)
; Base value: $10
; Max value: $c0 (quad-weak, STAB, good weather modifier
	; Struggle doesn't apply STAB or matchups
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	cp STRUGGLE
	ret z

	; Apply type matchups
	call BattleCheckTypeMatchup
	; Store TypeModifier (handles effectiveness)
	ld a, [wTypeMatchup]
	ld [TypeModifier], a
	and a
	jr nz, .not_immune
	; Immunities are treated as we missing and dealing 0 damage
	ld hl, CurDamage
	xor a
	ld [hli], a
	ld [hl], a
	; AttackMissed being nonzero can mean special immunity, so avoid overriding it
	ld a, [AttackMissed]
	and a
	ret nz
	ld a, 1
	ld [AttackMissed], a
	ret

.not_immune
	; Apply STAB
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	ld b, a
	ld a, [hBattleTurn]
	and a
	ld hl, BattleMonType1
	jr z, .got_attacker_types
	ld hl, EnemyMonType1
.got_attacker_types
	ld a, [hli]
	cp b
	jr z, .stab
	ld a, [hl]
	cp b
	jr nz, .stab_done
.stab
	; Adaptability gives 2x, otherwise STAB is 1.5x
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp ADAPTABILITY
	ld a, [wTypeMatchup]
	jr nz, .no_adaptability
	sla a
	ld [wTypeMatchup], a
	jr .stab_done
.no_adaptability
	ld b, a
	srl b
	add b
	ld [wTypeMatchup], a

.stab_done
	; Apply weather modifiers
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	ld b, a
	farcall DoWeatherModifiers

	; Now calculate the damage changes with the modifiers in mind.
	ld a, [wTypeMatchup]
	ld [hMultiplier], a
	xor a
	ld [hMultiplicand + 0], a
	ld hl, CurDamage
	ld a, [hli]
	ld [hMultiplicand + 1], a
	ld a, [hld]
	ld [hMultiplicand + 2], a
	call Multiply

	ld a, $10
	ld [hDivisor], a
	ld b, 4
	call Divide

	; Store in curDamage
	ld a, [hMultiplicand + 1]
	ld [hli], a
	ld b, a
	ld a, [hMultiplicand + 2]
	ld [hl], a
	or b
	ret nz

	; damage ended up 0, so set it to 1
	inc a
	ld [hl], a
	ret


BattleCheckTypeMatchup: ; 347c8
	ld hl, EnemyMonType1
	ld a, [hBattleTurn]
	and a
	jr z, CheckTypeMatchup
	ld hl, BattleMonType1

	; fallthrough
; 347d3

CheckTypeMatchup:
; FIXME: Broken in AI usage! (assumes placing move type in a will work, it wont)
; wrapper that handles ability immunities, because type matchups take predecence,
; this matters for Ground pokémon with Lightning Rod (and Trace edge-cases).
; Yes, Lightning Rod is useless on ground types since GSC has no doubles.
	push hl
	push de
	push bc
	call _CheckTypeMatchup
	; if the attack is ineffective, bypass ability checks
	ld a, [wTypeMatchup]
	and a
	jr z, .end
	farcall CheckNullificationAbilities
.end
	pop bc
	pop de
	pop hl
	ret

_CheckTypeMatchup: ; 347d3
	push hl
	ld de, 1 ; IsInArray checks below use single-byte arrays
; Handle powder moves
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	ld hl, PowderMoves
	call IsInArray
	jr nc, .skip_powder
	call CheckIfTargetIsGrassType
	jp z, .Immune
	call GetOpponentAbilityAfterMoldBreaker
	cp OVERCOAT
	jp z, .AbilImmune
.skip_powder
	pop hl
	push hl
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	ld d, a
	ld b, [hl]
	inc hl
	ld c, [hl]
	ld a, $10 ; 1.0
	ld [wTypeMatchup], a
	ld hl, InverseTypeMatchup
	ld a, [BattleType]
	cp BATTLETYPE_INVERSE
	jr z, .TypesLoop
	ld hl, TypeMatchup
.TypesLoop:
	ld a, [hli]
	; terminator
	cp $ff
	jr z, .End
	cp $fe
	jr nz, .Next
	; stuff beyond this point is ignored if the foe is identified or we have Scrappy
	ld a, BATTLE_VARS_SUBSTATUS1_OPP
	call GetBattleVar
	bit SUBSTATUS_IDENTIFIED, a
	jr nz, .End
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp SCRAPPY
	jp z, .End
	jr .TypesLoop

.Next:
	; attacking type
	cp d
	jr nz, .Nope
	ld a, [hli]
	; defending types
	cp b
	jr z, .Yup
	cp c
	jr z, .Yup
	jr .Nope2

.Nope:
	inc hl
.Nope2:
	inc hl
	jr .TypesLoop

.Yup:
	; no need to continue if we encountered a 0x matchup
	ld a, [hli]
	and a
	jr z, .Immune
	cp SUPER_EFFECTIVE
	jr z, .se
	cp NOT_VERY_EFFECTIVE
	jr z, .nve
	jr .TypesLoop
.se
	ld a, [wTypeMatchup]
	sla a
	ld [wTypeMatchup], a
	jr .TypesLoop
.nve
	ld a, [wTypeMatchup]
	srl a
	ld [wTypeMatchup], a
	jr .TypesLoop

.AbilImmune:
	; most abilities are checked seperately, but Overcoat ends up here (powder)
	ld a, 3
	ld [AttackMissed], a
.Immune:
	xor a
	ld [wTypeMatchup], a
.End:
	pop hl
	ret

; 34833


BattleCommand_ResetTypeMatchup: ; 34833
; Reset the type matchup multiplier to 1.0, if the type matchup is not 0.
; If there is immunity in play, the move automatically misses.
	call BattleCheckTypeMatchup
	ld a, [wTypeMatchup]
	and a
	ld a, $10 ; 1.0
	jr nz, .reset
	call ResetDamage
	xor a
	ld [TypeModifier], a
	inc a
	ld [AttackMissed], a
	ret

.reset
	ld [wTypeMatchup], a
	ret

; 3484e

INCLUDE "battle/ai/switch.asm"

TypeMatchup: ; 34bb1
INCLUDE "battle/type_matchup.asm"
; 34cfd

InverseTypeMatchup:
INCLUDE "battle/inverse_type_matchup.asm"


BattleCommand_DamageVariation: ; 34cfd
; damagevariation

; Modify the damage spread between 85% and 100%.

; Because of the method of division the probability distribution
; is not consistent. This makes the highest damage multipliers
; rarer than normal.


; No point in reducing 1 or 0 damage.
	ld hl, CurDamage
	ld a, [hli]
	and a
	jr nz, .go
	ld a, [hl]
	cp 2
	ret c

.go
	; Start with the current (100%) damage.
	xor a
	ld [hMultiplicand + 0], a
	dec hl
	ld a, [hli]
	ld [hMultiplicand + 1], a
	ld a, [hl]
	ld [hMultiplicand + 2], a

	; Multiply by 85-100%...
	ld a, 16
	call BattleRandomRange
	add 85
	ld [hMultiplier], a
	call Multiply

	; ...divide by 100%...
	ld a, 100
	ld [hDivisor], a
	ld b, $4
	call Divide

	; ...to get .85-1.00x damage.
	ld a, [hQuotient + 1]
	ld hl, CurDamage
	ld [hli], a
	ld a, [hQuotient + 2]
	ld [hl], a
	ret

; 34d32


BattleCommand_CheckHit: ; 34d32
; checkhit

	call .DreamEater
	jp z, .Miss

	call .Protect
	jp nz, .Miss_skipset

	call .Substitute
	jp nz, .Miss

	call .PoisonTypeUsingToxic
	ret z

	call .NoGuardCheck
	ret z

	call .FlyDigMoves
	jp nz, .Miss

	call .LockOn
	ret nz

	call .WeatherAccCheck
	ret z

	; Perfect-accuracy moves
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_ALWAYS_HIT
	ret z
	cp EFFECT_ROAR
	ret z
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	cp STRUGGLE
	ret z

	; Now doing usual accuracy check
	ld a, [PlayerAccLevel]
	ld b, a
	ld a, [EnemyEvaLevel]
	ld c, a
	ld a, [hBattleTurn]
	and a
	jr z, .got_acc_eva
	ld a, [EnemyAccLevel]
	ld b, a
	ld a, [PlayerEvaLevel]
	ld c, a

.got_acc_eva
	; Handle stat modifiers
	; Unaware ignores enemy stat changes, identification also does if above 0
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp UNAWARE
	jr z, .reset_evasion

	; check Foresight
	ld a, BATTLE_VARS_SUBSTATUS1_OPP
	call GetBattleVar
	bit SUBSTATUS_IDENTIFIED, a
	jr z, .check_opponent_unaware
	ld a, c
	cp 7
	jr c, .check_opponent_unaware
.reset_evasion
	ld c, 7
.check_opponent_unaware
	call GetOpponentAbilityAfterMoldBreaker
	cp UNAWARE
	jr nz, .no_opponent_unaware
	ld b, 7

.no_opponent_unaware
	; The way accuracy and evasion is combined
	; from generation III onwards is a bit unintuitive.
	; Instead of calcing them seperately, they
	; are both combined additively. For example,
	; acc-3 and eva+3 is 3/9, not 3/12. In addition,
	; the change is capped at -6 or +6
	ld a, 7
	add b
	sub c
	jr c, .min_acc
	jr z, .min_acc
	cp 14
	jr c, .got_acc_stat
	; max accuracy
	ld a, 13
	jr .got_acc_stat
.min_acc
	ld a, 1
.got_acc_stat
	ld b, a
	xor a
	ld [hMultiplicand + 0], a
	ld [hMultiplicand + 1], a
	ld a, BATTLE_VARS_MOVE_ACCURACY
	call GetBattleVar
	cp 255
	jr nz, .got_base_acc
	; If internal accuracy is 255, insert
	; $100 instead to avoid 1/256 miss
	ld a, 1
	ld [hMultiplicand + 1], a
	xor a
.got_base_acc
	ld [hMultiplicand + 2], a

	ld hl, hMultiplier
	ld a, b
	cp 7
	jr c, .accuracy_not_lowered
	; No need to multiply/divide if acc=eva
	jr z, .stat_changes_done

.accuracy_not_lowered
	; Multiply by min(acc-4,3)
	ld a, b
	sub 4
	cp 3
	jr nc, .got_multiplier
	ld a, 3
.got_multiplier
	ld [hl], a
	call Multiply
	; Divide by min(10-acc,3)
	ld a, 10
	sub b
	cp 3
	jr nc, .got_divisor
	ld a, 3
.got_divisor
	ld [hl], a
	ld b, 4
	call Divide
.stat_changes_done
	farcall ApplyAccuracyAbilities

	; Check items
	call GetOpponentItem
	ld a, b
	cp HELD_BRIGHTPOWDER
	jr nz, .brightpowder_done
	ld hl, hMultiplier
	ld a, 100
	ld [hl], a
	call Multiply
	ld a, 100
	add c
	ld [hl], a
	ld b, 4
	call Divide
.brightpowder_done
	; Accuracy modifiers done. Grab data
	; from hMultiplicand
	ld a, [hMultiplicand + 0]
	ld b, a
	ld a, [hMultiplicand + 1]
	or b
	jr nz, .Hit ; final acc ended up >=100%
	ld a, [hMultiplicand + 2]
	ld b, a
	call BattleRandom
	cp b
	jr nc, .Miss

.Hit:
	ret


.Miss:
; Keep the damage value intact if we're using (Hi) Jump Kick.
	ld a, 1
.Miss_skipset:
; Used to set a special value to AttackMissed for message customization
	ld [AttackMissed], a
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_JUMP_KICK
	call nz, ResetDamage
	ret


.DreamEater:
; Return z if we're trying to eat the dream of
; a monster that isn't sleeping.
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_DREAM_EATER
	ret nz

	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVar
	and SLP
	ret


.Protect:
; Return nz if the opponent is protected.
	ld a, BATTLE_VARS_SUBSTATUS1_OPP
	call GetBattleVar
	bit SUBSTATUS_PROTECT, a
	ret z
	ld a, 2
	and a
	ret


.Substitute:
; Return nz if the opponent is behind a Substitute for certain moves
	call CheckSubstituteOpp
	jr z, .not_blocked
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	cp SWAGGER
	jr z, .blocked
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_TRAP
	jr z, .blocked
.not_blocked
	xor a
	and a
	ret
.blocked
	ld a, 1
	and a
	ret


.LockOn:
; Return nz if we are locked-on and aren't trying to use Earthquake
; or Magnitude on a monster that is flying.
	ld a, BATTLE_VARS_SUBSTATUS2_OPP
	call GetBattleVarAddr
	bit SUBSTATUS_LOCK_ON, [hl]
	res SUBSTATUS_LOCK_ON, [hl]
	ret z

	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVar
	bit SUBSTATUS_FLYING, a
	jr z, .LockedOn

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar

	cp EARTHQUAKE
	ret z
	cp MAGNITUDE
	ret z

.LockedOn:
	ld a, 1
	and a
	ret


.PoisonTypeUsingToxic:
; Return z if we are a Poison-type using Toxic.
	call CheckIfUserIsPoisonType
	ret nz
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	cp TOXIC
	ret


.FlyDigMoves:
; Check for moves that can hit underground/flying opponents.
; Return z if the current move can hit the opponent.

	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVar
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	ret z

	bit SUBSTATUS_FLYING, a
	jr z, .DigMoves

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar

	cp GUST
	ret z
	cp THUNDER
	ret z
	cp TWISTER
	ret z
	cp HURRICANE
	ret

.DigMoves:
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar

	cp EARTHQUAKE
	ret z
	cp MAGNITUDE
	ret


.WeatherAccCheck:
; Returns z if the move used always hits in the current weather
	call GetWeatherAfterCloudNine
	cp WEATHER_RAIN
	jr z, .RainAccCheck
	cp WEATHER_HAIL
	jr z, .HailAccCheck
	ret

.RainAccCheck:
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar

	cp THUNDER
	ret z
	cp HURRICANE
	ret

.HailAccCheck:
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar

	cp BLIZZARD
	ret

.NoGuardCheck:
	ld a, [PlayerAbility]
	cp NO_GUARD
	ret z
	ld a, [EnemyAbility]
	cp NO_GUARD
	ret


BattleCommand_EffectChance: ; 34ecc
; effectchance
	push bc
	push hl
	xor a
	ld [EffectFailed], a
	call CheckSubstituteOpp
	jr nz, .failed

	call GetOpponentAbilityAfterMoldBreaker
	cp SHIELD_DUST
	jr z, .failed

	ld hl, wPlayerMoveStruct + MOVE_CHANCE
	ld a, [hBattleTurn]
	and a
	jr z, .got_move_chance
	ld hl, wEnemyMoveStruct + MOVE_CHANCE
.got_move_chance

	ld a, [hl]
	ld b, a
	ld a, BATTLE_VARS_ABILITY
	cp SHEER_FORCE
	jr z, .failed
	cp SERENE_GRACE
	jr nz, .skip_serene_grace
	sla b
	jr c, .end ; Carry means the effect byte overflowed, so gurantee it

.skip_serene_grace
	call BattleRandom
	cp b
	jr c, .end

.failed
	ld a, 1
	ld [EffectFailed], a
	and a
.end
	pop hl
	pop bc
	ret

; 34eee


BattleCommand_LowerSub: ; 34eee
; lowersub

	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVar
	bit SUBSTATUS_SUBSTITUTE, a
	ret z

	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVar
	bit SUBSTATUS_CHARGED, a
	jr nz, .already_charged

	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_RAZOR_WIND
	jr z, .charge_turn
	cp EFFECT_SKY_ATTACK
	jr z, .charge_turn
	cp EFFECT_SKULL_BASH
	jr z, .charge_turn
	cp EFFECT_SOLAR_BEAM
	jr z, .charge_turn
	cp EFFECT_FLY
	jr z, .charge_turn

.already_charged
	call .Rampage
	jr z, .charge_turn

	call CheckUserIsCharging
	ret nz

.charge_turn
	call _CheckBattleEffects
	jr c, .mimic_anims

	xor a
	ld [wNumHits], a
	ld [FXAnimIDHi], a
	inc a
	ld [wKickCounter], a
	ld a, SUBSTITUTE
	jp LoadAnim

.mimic_anims
	call BattleCommand_LowerSubNoAnim
	jp BattleCommand_MoveDelay

.Rampage:
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_ROLLOUT
	jr z, .rollout_rampage
	cp EFFECT_RAMPAGE
	jr z, .rollout_rampage

	ld a, 1
	and a
	ret

.rollout_rampage
	ld a, [wSomeoneIsRampaging]
	and a
	ld a, 0 ; not xor a; preserve carry flag
	ld [wSomeoneIsRampaging], a
	ret

; 34f57


BattleCommand_HitTarget: ; 34f57
; hittarget
	call BattleCommand_LowerSub
	call BattleCommand_HitTargetNoSub
	jp BattleCommand_RaiseSub

; 34f60


BattleCommand_HitTargetNoSub: ; 34f60
	ld a, [AttackMissed]
	and a
	jp nz, BattleCommand_MoveDelay

	ld a, [hBattleTurn]
	and a
	ld de, PlayerRolloutCount
	ld a, BATTLEANIM_ENEMY_DAMAGE
	jr z, .got_rollout_count
	ld de, EnemyRolloutCount
	ld a, BATTLEANIM_PLAYER_DAMAGE

.got_rollout_count
	ld [wNumHits], a
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_MULTI_HIT
	jr z, .multihit
	cp EFFECT_CONVERSION
	jr z, .conversion
	cp EFFECT_DOUBLE_HIT
	jr z, .doublehit
	cp EFFECT_TRIPLE_KICK
	jr z, .triplekick
	xor a
	ld [wKickCounter], a

.triplekick

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld e, a
	ld d, 0
	call PlayFXAnimID

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	cp FLY
	jr z, .fly_dig
	cp DIG
	ret nz

.fly_dig
; clear sprite
	jp AppearUserLowerSub

.multihit
.conversion
.doublehit
	ld a, [wKickCounter]
	and 1
	xor 1
	ld [wKickCounter], a
	ld a, [de]
	cp $1
	push af
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld e, a
	ld d, 0
	pop af
	jp z, PlayFXAnimID
	xor a
	ld [wNumHits], a
	jp PlayFXAnimID

; 34fd1


BattleCommand_StatUpAnim: ; 34fd1
	ld a, [AttackMissed]
	and a
	jp nz, BattleCommand_MoveDelay

	xor a
	jr BattleCommand_StatUpDownAnim

; 34fdb


BattleCommand_StatDownAnim: ; 34fdb
	ld a, [AttackMissed]
	and a
	jp nz, BattleCommand_MoveDelay

	ld a, [hBattleTurn]
	and a
	ld a, BATTLEANIM_ENEMY_STAT_DOWN
	jr z, BattleCommand_StatUpDownAnim
	ld a, BATTLEANIM_WOBBLE

	; fallthrough
; 34feb


BattleCommand_StatUpDownAnim: ; 34feb
	ld [wNumHits], a
	xor a
	ld [wKickCounter], a
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld e, a
	ld d, 0
	jp PlayFXAnimID

; 34ffd


BattleCommand_SwitchTurn: ; 34ffd
; switchturn

	ld a, [hBattleTurn]
	xor 1
	ld [hBattleTurn], a
	ret

; 35004


BattleCommand_RaiseSub: ; 35004
; raisesub

	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVar
	bit SUBSTATUS_SUBSTITUTE, a
	ret z

	call _CheckBattleEffects
	jp c, BattleCommand_RaiseSubNoAnim

	xor a
	ld [wNumHits], a
	ld [FXAnimIDHi], a
	ld a, $2
	ld [wKickCounter], a
	ld a, SUBSTITUTE
	jp LoadAnim

; 35023


BattleCommand_FailureText: ; 35023
; failuretext
; If the move missed or failed, load the appropriate
; text, and end the effects of multi-turn or multi-
; hit moves.
	ld a, [AttackMissed]
	and a
	ret z

	call GetFailureResultText
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVarAddr

	cp FLY
	jr z, .fly_dig
	cp DIG
	jr z, .fly_dig

; Move effect:
	inc hl
	ld a, [hl]

	cp EFFECT_MULTI_HIT
	jr z, .multihit
	cp EFFECT_DOUBLE_HIT
	jr z, .multihit
	jp EndMoveEffect

.multihit
	call BattleCommand_RaiseSub
	jp EndMoveEffect

.fly_dig
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	res SUBSTATUS_UNDERGROUND, [hl]
	res SUBSTATUS_FLYING, [hl]
	call AppearUserRaiseSub
	jp EndMoveEffect

; 3505e


BattleCommand_CheckFaint: ; 3505e
; checkfaint

	ld a, BATTLE_VARS_SUBSTATUS1_OPP
	call GetBattleVar
	bit SUBSTATUS_ENDURE, a
	jr z, .not_enduring
	call BattleCommand_FalseSwipe
	ld b, $0
	jr nc, .okay
	ld b, $1
	jr .okay

.not_enduring
	call GetOpponentItem
	ld a, b
	cp HELD_FOCUS_BAND
	ld b, $0
	jr nz, .okay
	call BattleRandom
	cp c
	jr nc, .okay
	call BattleCommand_FalseSwipe
	ld b, $0
	jr nc, .okay
	ld b, $2
.okay
	push bc
	call .check_sub
	ld c, $0
	ld a, [hBattleTurn]
	and a
	jr nz, .damage_player
	call EnemyHurtItself
	jr .done_damage

.damage_player
	call PlayerHurtItself

.done_damage
	pop bc
	ld a, b
	and a
	ret z
	dec a
	jr nz, .not_enduring2
	ld hl, EnduredText
	jp StdBattleTextBox

.not_enduring2
	call GetOpponentItem
	ld a, [hl]
	ld [wNamedObjectIndexBuffer], a
	call GetItemName

	ld hl, HungOnText
	jp StdBattleTextBox

.check_sub
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp INFILTRATOR
	jr z, .bypass_sub
	ld a, BATTLE_VARS_SUBSTATUS4_OPP
	call GetBattleVar
	bit SUBSTATUS_SUBSTITUTE, a
	ret nz
.bypass_sub
	ld de, PlayerDamageTaken + 1
	ld a, [hBattleTurn]
	and a
	jr nz, .damage_taken
	ld de, EnemyDamageTaken + 1

.damage_taken
	ld a, [CurDamage + 1]
	ld b, a
	ld a, [de]
	add b
	ld [de], a
	dec de
	ld a, [CurDamage]
	ld b, a
	ld a, [de]
	adc b
	ld [de], a
	ret nc
	ld a, $ff
	ld [de], a
	inc de
	ld [de], a
	ret

; 350e4


GetFailureResultText: ; 350e4
	ld hl, DoesntAffectText
	ld a, [TypeModifier]
	and a
	jr z, .got_text
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_FUTURE_SIGHT
	ld hl, ButItFailedText
	jr z, .got_text
	ld hl, AttackMissedText
	ld a, [CriticalHit]
	cp $ff
	jr nz, .got_text
	ld hl, UnaffectedText
.got_text
	call FailText_CheckOpponentProtect
	xor a
	ld [CriticalHit], a

	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_JUMP_KICK
	ret nz

	ld a, [TypeModifier]
	and a
	ret z

	ld hl, CurDamage
	ld a, [hli]
	ld b, [hl]
rept 3
	srl a
	rr b
endr
	ld [hl], b
	dec hl
	ld [hli], a
	or b
	jr nz, .do_at_least_1_damage
	inc a
	ld [hl], a
.do_at_least_1_damage
	ld hl, CrashedText
	call StdBattleTextBox
	ld a, $1
	ld [wKickCounter], a
	call LoadMoveAnim
	ld c, $1
	ld a, [hBattleTurn]
	and a
	jp nz, EnemyHurtItself
	jp PlayerHurtItself

FailText_CheckOpponentProtect: ; 35157
; Print an appropriate failure message, usually AttackMissed.
; An AttackMissed value of something other than 1 can override
; the message, used for Protect and some abilities.
; Important: To ensure proper message order, AttackMissed=3
; has side effects -- it triggers the ability.
; TODO: perhaps an enum?
	ld a, [AttackMissed]
	cp 1
	jr z, .printmsg
	cp 2
	jr z, .protected
	cp 3
	jr z, .ability_immune
	jr .printmsg ; just in case
.protected
	ld hl, ProtectingItselfText
.printmsg
	jp StdBattleTextBox
.ability_immune
	farcall RunEnemyNullificationAbilities
	ret

; 35165


BattleCommand_CriticalText: ; 35175
; criticaltext
; Prints the message for critical hits.

; If there is no message to be printed, wait 20 frames.
	ld a, [CriticalHit]
	and a
	jr z, .wait

	ld hl, CriticalHitText
	call StdBattleTextBox

	xor a
	ld [CriticalHit], a

	; Activate Anger Point here to get proper message order
	call GetOpponentAbilityAfterMoldBreaker
	cp ANGER_POINT
	jr nz, .wait
	call SwitchTurn
	farcall AngerPointAbility
	call SwitchTurn

.wait
	ld c, 20
	jp DelayFrames


BattleCommand_StartLoop: ; 35197
; startloop

	ld hl, PlayerRolloutCount
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld hl, EnemyRolloutCount
.ok
	xor a
	ld [hl], a
	ret

; 351a5


BattleCommand_SuperEffectiveLoopText: ; 351a5
; supereffectivelooptext

	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	bit SUBSTATUS_IN_LOOP, a
	ret nz

	; fallthrough
; 351ad


BattleCommand_SuperEffectiveText: ; 351ad
; supereffectivetext

	ld a, [TypeModifier]
	cp $10 ; 1.0
	ret z
	ld hl, SuperEffectiveText
	jr nc, .print
	ld hl, NotVeryEffectiveText
.print
	jp StdBattleTextBox

; 351c0


BattleCommand_PostFaintEffects: ; 351c0
; Effects that run after faint by an attack (Destiny Bond, Moxie, Aftermath, etc)
	ld hl, EnemyMonHP
	ld a, [hBattleTurn]
	and a
	jr z, .got_hp
	ld hl, BattleMonHP

.got_hp
	ld a, [hli]
	or [hl]
	ret nz

	ld a, BATTLE_VARS_SUBSTATUS2_OPP
	call GetBattleVar
	bit SUBSTATUS_DESTINY_BOND, a
	jr z, .no_dbond

	ld hl, TookDownWithItText
	call StdBattleTextBox

	farcall GetMaxHP
	farcall SubtractHPFromUser
	call SwitchTurn
	xor a
	ld [wNumHits], a
	ld [FXAnimIDHi], a
	inc a
	ld [wKickCounter], a
	ld a, DESTINY_BOND
	call LoadAnim
	call SwitchTurn

	ld a, [hBattleTurn]
	and a
	jr nz, .enemy_dbond
	call UpdateBattleMonInParty
	jr .finish
.enemy_dbond
	call UpdateEnemyMonInParty
	jr .finish

.no_dbond
	farcall RunFaintAbilities
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_MULTI_HIT
	jr z, .multiple_hit_raise_sub
	cp EFFECT_DOUBLE_HIT
	jr z, .multiple_hit_raise_sub
	cp EFFECT_TRIPLE_KICK
	jr nz, .finish

.multiple_hit_raise_sub
	call BattleCommand_RaiseSub

.finish
	jp EndMoveEffect

; 35250


BattleCommand_PostHitEffects: ; 35250
; previously buildopponentrage
	call CheckSubstituteOpp
	ret nz

	ld a, [AttackMissed]
	and a
	ret nz

	farcall RunHitAbilities

.start_rage
	ld a, BATTLE_VARS_SUBSTATUS4_OPP
	call GetBattleVar
	bit SUBSTATUS_RAGE, a
	ret z

	call SwitchTurn
	call ResetMiss
	call BattleCommand_AttackUp

	; don't print a failure message if we're maxed out in atk
	ld a, [FailedMessage]
	and a
	jp z, SwitchTurn

	ld hl, RageBuildingText
	call StdBattleTextBox
	call BattleCommand_StatUpMessage
	jp SwitchTurn

; 3527b


BattleCommand_RageDamage: ; 3527b
; unused (Rage is now Attack boosts again)
	ret


EndMoveEffect: ; 352a3
	ld a, [BattleScriptBufferLoc]
	ld l, a
	ld a, [BattleScriptBufferLoc + 1]
	ld h, a
	ld a, $ff
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ret

; 352b1


DittoMetalPowder: ; 352b1
	ld a, MON_SPECIES
	call BattlePartyAttr
	ld a, [hBattleTurn]
	and a
	ld a, [hl]
	jr nz, .Ditto
	ld a, [TempEnemyMonSpecies]

.Ditto:
	cp DITTO
	ret nz

	push bc
	call GetOpponentItem
	ld a, [hl]
	cp METAL_POWDER
	pop bc
	ret nz

	ld a, c
	srl a
	add c
	ld c, a
	ret nc

	srl b
	ld a, b
	and a
	jr nz, .done
	inc b
.done
	scf
	rr c
	ret

; 352dc


UnevolvedEviolite:
	ld a, MON_SPECIES
	call BattlePartyAttr
	ld a, [hBattleTurn]
	and a
	ld a, [hl]
	jr nz, .Unevolved
	ld a, [TempEnemyMonSpecies]

.Unevolved:
	dec a
	push hl
	push bc
	ld b, 0
	ld c, a
	ld hl, EvosAttacksPointers
rept 2
	add hl, bc
endr
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld a, [hli]
	and a
	pop bc
	pop hl
	ret z

	push bc
	call GetOpponentItem
	ld a, [hl]
	cp EVIOLITE
	pop bc
	ret nz

	ld a, c
	srl a
	add c
	ld c, a
	ret nc

	srl b
	ld a, b
	and a
	jr nz, .done
	inc b
.done
	scf
	rr c
	ret


BattleCommand_DamageStats: ; 352dc
; damagestats

	ld a, [hBattleTurn]
	and a
	jp nz, EnemyAttackDamage

	; fallthrough
; 352e2


PlayerAttackDamage: ; 352e2
; Return move power d, player level e, enemy defense c and player attack b.

	call ResetDamage

; No damage dealt with 0 power.
	ld hl, wPlayerMoveStructPower
	ld a, [hl]
	and a
	ld d, a
	ret z

	ld hl, wPlayerMoveStructCategory
	ld a, [hl]
	cp SPECIAL
	jr nc, .special

.physical
	ld hl, EnemyMonDefense
	ld a, [hli]
	ld b, a
	ld c, [hl]

if !DEF(FAITHFUL)
	call HailDefenseBoost
endc

	ld a, [EnemyAbility]
	cp INFILTRATOR
	jr z, .physicalcrit
	ld a, [EnemyScreens]
	bit SCREENS_REFLECT, a
	jr z, .physicalcrit
	sla c
	rl b

.physicalcrit
	ld hl, BattleMonAttack
	call GetDamageStatsCritical
	jr c, .thickcluborlightball

	ld hl, EnemyStats + 2
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld hl, PlayerStats
	jr .thickcluborlightball

.special
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_PSYSTRIKE
	jr z, .psystrike

	ld hl, EnemyMonSpclDef
	ld a, [hli]
	ld b, a
	ld c, [hl]

	call SandstormSpDefBoost

	jp .lightscreen

.psystrike
	ld hl, EnemyMonDefense
	ld a, [hli]
	ld b, a
	ld c, [hl]

.lightscreen
	ld a, [EnemyAbility]
	cp INFILTRATOR
	jr z, .specialcrit
	ld a, [EnemyScreens]
	bit SCREENS_LIGHT_SCREEN, a
	jr z, .specialcrit
	sla c
	rl b

.specialcrit
	ld hl, BattleMonSpclAtk
	call GetDamageStatsCritical
	jr c, .lightball

	ld hl, EnemyStats + SP_DEFENSE * 2
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld hl, PlayerStats + SP_ATTACK * 2

.lightball
; Note: Returns player special attack at hl in hl.
	call LightBallBoost
	jr .done

.thickcluborlightball
; Note: Returns player attack at hl in hl.
	call ThickClubOrLightBallBoost

.done
	call TruncateHL_BC

	ld a, [BattleMonLevel]
	ld e, a
	call DittoMetalPowder
	call UnevolvedEviolite

	ld a, 1
	and a
	ret

; 3534d


EnemyAttackDamage: ; 353f6
; Return move power d, enemy level e, player defense c and enemy attack b.

	call ResetDamage

; No damage dealt with 0 power.
	ld hl, wEnemyMoveStructPower
	ld a, [hl]
	and a
	ld d, a
	ret z

	ld hl, wEnemyMoveStructCategory
	ld a, [hl]
	cp SPECIAL
	jr nc, .special

.physical
	ld hl, BattleMonDefense
	ld a, [hli]
	ld b, a
	ld c, [hl]

if !DEF(FAITHFUL)
	call HailDefenseBoost
endc

	ld a, [PlayerAbility]
	cp INFILTRATOR
	jr z, .physicalcrit
	ld a, [PlayerScreens]
	bit SCREENS_REFLECT, a
	jr z, .physicalcrit
	sla c
	rl b

.physicalcrit
	ld hl, EnemyMonAttack
	call GetDamageStatsCritical
	jr c, .thickcluborlightball

	ld hl, PlayerStats + 2
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld hl, EnemyStats
	jr .thickcluborlightball

.special
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_PSYSTRIKE
	jr z, .psystrike

	ld hl, BattleMonSpclDef
	ld a, [hli]
	ld b, a
	ld c, [hl]

	call SandstormSpDefBoost

	jp .lightscreen

.psystrike
	ld hl, BattleMonDefense
	ld a, [hli]
	ld b, a
	ld c, [hl]

.lightscreen
	ld a, [PlayerAbility]
	cp INFILTRATOR
	jr z, .specialcrit
	ld a, [PlayerScreens]
	bit SCREENS_LIGHT_SCREEN, a
	jr z, .specialcrit
	sla c
	rl b

.specialcrit
	ld hl, EnemyMonSpclAtk
	call GetDamageStatsCritical
	jr c, .lightball

	ld hl, PlayerStats + SP_DEFENSE * 2
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld hl, EnemyStats + SP_ATTACK * 2

.lightball
; Note: Returns enemy special attack at hl in hl.
	call LightBallBoost
	jr .done

.thickcluborlightball
; Note: Returns enemy attack at hl in hl.
	call ThickClubOrLightBallBoost

.done
	call TruncateHL_BC

	ld a, [EnemyMonLevel]
	ld e, a
	call DittoMetalPowder
	call UnevolvedEviolite

	ld a, 1
	and a
	ret

; 35461


TruncateHL_BC: ; 3534d
.loop
; Truncate 16-bit values hl and bc to 8-bit values b and c respectively.
; b = hl, c = bc

	ld a, h
	or b
	jr z, .finish

	srl b
	rr c
	srl b
	rr c

	ld a, c
	or b
	jr nz, .done_bc
	inc c

.done_bc
	srl h
	rr l
	srl h
	rr l

	ld a, l
	or h
	jr nz, .finish
	inc l

.finish
	ld a, [wLinkMode]
	cp 3
	jr z, .done
; If we go back to the loop point,
; it's the same as doing this exact
; same check twice.
	ld a, h
	or b
	jr nz, .loop

.done
	ld b, l
	ret

; 35378


GetDamageStatsCritical: ; 35378
; Return carry if non-critical.

	ld a, [CriticalHit]
	and a
	scf
	ret z

	; fallthrough
; 3537e


GetDamageStats: ; 3537e
; Return the attacker's offensive stat and the defender's defensive
; stat based on whether the attacking type is physical or special.

	push hl
	push bc
	ld a, [hBattleTurn]
	and a
	jr nz, .enemy
	ld a, [wPlayerMoveStructCategory]
	cp SPECIAL
; special
	ld a, [PlayerSAtkLevel]
	ld b, a
	ld a, [EnemySDefLevel]
	jr nc, .end
; physical
	ld a, [PlayerAtkLevel]
	ld b, a
	ld a, [EnemyDefLevel]
	jr .end

.enemy
	ld a, [wEnemyMoveStructCategory]
	cp SPECIAL
; special
	ld a, [EnemySAtkLevel]
	ld b, a
	ld a, [PlayerSDefLevel]
	jr nc, .end
; physical
	ld a, [EnemyAtkLevel]
	ld b, a
	ld a, [PlayerDefLevel]
.end
	cp b
	pop bc
	pop hl
	ret

; 353b5


ThickClubOrLightBallBoost: ; 353b5
; Return in hl the stat value at hl.

; If the attacking monster is Cubone or Marowak and
; it's holding a Thick Club, or if it's Pikachu and
; it's holding a Light Ball, double it.
	push bc
	push de

	push hl
	ld a, MON_SPECIES
	call BattlePartyAttr
	ld a, [hBattleTurn]
	and a
	ld a, [hl]
	jr z, .checkpikachu
	ld a, [TempEnemyMonSpecies]
.checkpikachu:
	pop hl
	cp PIKACHU
	jr z, .lightball

	ld b, CUBONE
	ld c, MAROWAK
	ld d, THICK_CLUB
	call SpeciesItemBoost
	jp .done

.lightball
	ld b, PIKACHU
	ld c, PIKACHU
	ld d, LIGHT_BALL
	call SpeciesItemBoost

.done
	pop de
	pop bc
	ret

; 353c3


LightBallBoost: ; 353c3
; Return in hl the stat value at hl.

; If the attacking monster is Pikachu and it's
; holding a Light Ball, double it.
	push bc
	push de
	ld b, PIKACHU
	ld c, PIKACHU
	ld d, LIGHT_BALL
	call SpeciesItemBoost
	pop de
	pop bc
	ret

; 353d1


SpeciesItemBoost: ; 353d1
; Return in hl the stat value at hl.

; If the attacking monster is species b or c and
; it's holding item d, double it.

	ld a, [hli]
	ld l, [hl]
	ld h, a

	push hl
	ld a, MON_SPECIES
	call BattlePartyAttr
	ld a, [hBattleTurn]
	and a
	ld a, [hl]
	jr z, .CompareSpecies
	ld a, [TempEnemyMonSpecies]
.CompareSpecies:
	pop hl

	cp b
	jr z, .GetItemHeldEffect
	cp c
	ret nz

.GetItemHeldEffect:
	push hl
	call GetUserItem
	ld a, [hl]
	pop hl
	cp d
	ret nz

; Double the stat
	sla l
	rl h
	ret

; 353f6


SandstormSpDefBoost:
	call GetWeatherAfterCloudNine
	cp WEATHER_SANDSTORM
	ret nz
	call CheckIfTargetIsRockType
	ret z
	push hl
	ld h, b
	ld l, c
	sla l
	rl h
	add hl, bc
	ld b, h
	ld c, l
	pop hl
	ret


HailDefenseBoost:
	call GetWeatherAfterCloudNine
	cp WEATHER_HAIL
	ret nz
	call CheckIfTargetIsIceType
	ret z
	push hl
	ld h, b
	ld l, c
	sla l
	rl h
	add hl, bc
	ld b, h
	ld c, l
	pop hl
	ret


; Unused, but kept for now to avoid random bugs
BattleCommand_StoreEnergy:
BattleCommand_UnleashEnergy:
	jp EndMoveEffect
BattleCommand_BeatUp:
BattleCommand_PsychUp:
BattleCommand_FrustrationPower:
BattleCommand_Present:
BattleCommand_Spite:
BattleCommand_DefrostOpponent:
BattleCommand_Conversion2:
BattleCommand_Snore:
BattleCommand_OHKO:
BattleCommand_MirrorMove:
BattleCommand_Mimic:
BattleCommand_Nightmare:
	ret


BattleCommand_ClearMissDamage: ; 355d5
; clearmissdamage
	ld a, [AttackMissed]
	and a
	ret z

	jp ResetDamage

; 355dd


HitSelfInConfusion: ; 355dd
	call ResetDamage
	ld a, [hBattleTurn]
	and a
	ld hl, BattleMonDefense
	ld de, PlayerScreens
	ld a, [BattleMonLevel]
	jr z, .got_it

	ld hl, EnemyMonDefense
	ld de, EnemyScreens
	ld a, [EnemyMonLevel]
.got_it
	push af
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld a, [de]
	bit SCREENS_REFLECT, a
	jr z, .mimic_screen

	sla c
	rl b
.mimic_screen
rept 3
	dec hl
endr
	ld a, [hli]
	ld l, [hl]
	ld h, a
	call TruncateHL_BC
	ld d, 40
	pop af
	ld e, a
	ret

; 35612


BattleCommand_DamageCalc: ; 35612
; damagecalc

; Return a damage value for move power d, player level e, enemy defense c and player attack b.

; Return 1 if successful, else 0.

	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar

; Variable-hit moves and Conversion can have a power of 0.
	cp EFFECT_MULTI_HIT
	jr z, .skip_zero_damage_check

	cp EFFECT_CONVERSION
	jr z, .skip_zero_damage_check

; No damage if move power is 0.
	ld a, d
	and a
	ret z

.skip_zero_damage_check
; Minimum defense value is 1.
	ld a, c
	and a
	jr nz, .not_dividing_by_zero
	ld c, 1
.not_dividing_by_zero

	xor a
	ld hl, hDividend
	ld [hli], a
	ld [hli], a
	ld [hl], a

; Level * 2
	ld a, e
	add a
	jr nc, .level_not_overflowing
	ld [hl], $1
.level_not_overflowing
	inc hl
	ld [hli], a

; / 5
	ld a, 5
	ld [hld], a
	push bc
	ld b, $4
	call Divide
	pop bc

; + 2
	inc [hl]
	inc [hl]

; Technician needs to be checked before other abilities because of
; being move power-dependant.
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp TECHNICIAN
	jr nz, .skip_technician
	ld a, d
	cp 61 ; Technician applies for moves with 60BP or less.
	jr c, .skip_technician
	srl a
	add d
	ld d, a

.skip_technician
; * bp
	inc hl
	ld [hl], d
	call Multiply

; * Attack
	ld [hl], b
	call Multiply

; / Defense
	ld [hl], c
	ld b, $4
	call Divide

; / 50
	ld [hl], 50
	ld b, $4
	call Divide

; Ability boosts. Some are done elsewhere depending on needs.
; TODO: Make this easier to follow (move to a seperate routine perhaps)
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp HUGE_POWER
	jp z, .ability_double
	cp HUSTLE
	jp z, .ability_semidouble
	cp OVERGROW
	jr z, .overgrow
	cp BLAZE
	jr z, .blaze
	cp TORRENT
	jr z, .torrent
	cp SWARM
	jr z, .swarm
	cp SHEER_FORCE
	jr z, .sheer_force
	cp ANALYTIC
	jr z, .analytic
	cp TINTED_LENS
	jr z, .tinted_lens
	cp SOLAR_POWER
	jr z, .solar_power
	cp IRON_FIST
	jr z, .iron_fist
	cp SAND_FORCE
	jr z, .sand_force
	cp RECKLESS
	jp z, .reckless
	cp GUTS
	jp nz, .ability_penalties
	ld a, BATTLE_VARS_STATUS
	call GetBattleVar
	and a
	jp z, .ability_penalties
	jp .ability_semidouble
.overgrow
	ld b, GRASS
	jr .pinch_ability
.blaze
	ld b, FIRE
	jr .pinch_ability
.torrent
	ld b, WATER
	jr .pinch_ability
.swarm
	ld b, BUG
.pinch_ability
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	cp b
	jp nz, .ability_penalties
	call CheckPinch
	jp z, .ability_semidouble
	jp .ability_penalties
.sheer_force
	; Only nonzero for sheer force users when using a move with an additional effect
	ld a, [EffectFailed]
	and a
	jp z, .ability_penalties
	jr .ability_x1_3
.analytic
	call CheckOpponentWentFirst
	jp z, .ability_penalties
	jr .ability_x1_3
.tinted_lens
	ld a, [TypeModifier]
	cp $10 ; x1
	jr nc, .ability_penalties
	jr .ability_double
.solar_power
	call GetWeatherAfterCloudNine
	cp WEATHER_SUN
	jr nz, .ability_penalties
	jr .ability_semidouble
.iron_fist
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	push hl
	ld hl, PunchingMoves
	call IsInArray
	pop hl
	jr c, .ability_penalties
	jr .ability_x1_2
.sand_force
	call GetWeatherAfterCloudNine
	cp WEATHER_SANDSTORM
	jr nz, .ability_penalties
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	cp GROUND
	jr z, .ability_x1_3
	cp ROCK
	jr z, .ability_x1_3
	cp STEEL
	jr z, .ability_x1_3
	jr .ability_penalties
.reckless
	; skip Struggle
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	cp STRUGGLE
	jr z, .ability_penalties
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_RECOIL_HIT
	jr z, .ability_x1_2
	cp EFFECT_JUMP_KICK
	jr nz, .ability_penalties
.ability_x1_2
	; x1.2
	ld [hl], 6
	call Multiply
	ld [hl], 5
	ld b, $4
	call Divide
	jr .ability_penalties
.ability_x1_3
	ld [hl], 13
	call Multiply
	ld [hl], 10
	ld b, $4
	call Divide
	jr .ability_penalties
.ability_semidouble
	; x1.5
	ld [hl], 3
	call Multiply
	ld [hl], 2
	ld b, $4
	call Divide
	jr .ability_penalties
.ability_double
	; x2
	ld [hl], 2
	call Multiply

.ability_penalties
	call GetOpponentAbilityAfterMoldBreaker
	cp MULTISCALE
	jr nz, .skip_multiscale
	push hl
	call SwitchTurn
	ld hl, CheckFullHP_b
	call CallBattleCore
	call SwitchTurn
	pop hl
	ld a, b
	and a
	jp nz, .abilities_done
	ld [hl], 2
	ld b, $4
	call Divide
	jp .abilities_done
.skip_multiscale
	cp MARVEL_SCALE
	jr nz, .skip_marvelscale
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVar
	and a
	jp z, .abilities_done
	ld [hl], 2
	call Multiply
	ld [hl], 3
	ld b, $4
	call Divide
	jr .abilities_done
.skip_marvelscale
; These do the same thing
	cp SOLID_ROCK
	jr z, .solid_rock
	cp FILTER
	jr nz, .skip_solid_rock
.solid_rock
; Check super effective status
	ld a, [TypeModifier]
	cp $10 ; x1
	jr z, .abilities_done
	jr c, .abilities_done
	ld [hl], 3
	call Multiply
	ld [hl], 4
	ld b, $4
	call Divide
	jr .abilities_done
.skip_solid_rock
	cp THICK_FAT
	jr nz, .skip_thick_fat
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	cp FIRE
	jr z, .thick_fat_ok
	cp ICE
	jr nz, .abilities_done
.thick_fat_ok
	ld [hl], 2
	ld b, $4
	call Divide
	jr .abilities_done
.skip_thick_fat
	cp DRY_SKIN
	jr nz, .skip_dry_skin
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	cp FIRE
	jr nz, .abilities_done
	ld [hl], 5
	call Multiply
	ld [hl], 4
	ld b, $4
	call Divide
.skip_dry_skin
	cp FUR_COAT
	jr nz, .abilities_done
	ld a, BATTLE_VARS_MOVE_CATEGORY
	call GetBattleVar
	cp PHYSICAL
	jr z, .fur_coat_ok
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	cp PSYSTRIKE
	jr nz, .abilities_done
.fur_coat_ok
	ld [hl], 2
	ld b, $4
	call Divide
	jr .abilities_done
.abilities_done
; Flash Fire
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVar
	bit SUBSTATUS_FLASH_FIRE, a
	jr z, .no_flash_fire
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	cp FIRE
	jr nz, .no_flash_fire
	ld [hl], 3
	call Multiply
	ld [hl], 2
	ld b, $4
	call Divide

.no_flash_fire
; Critical hits
	ld a, [CriticalHit]
	and a
	jr z, .no_crit

	ld [hl], 6
	call Multiply
	ld [hl], 4
	ld a, BATTLE_VARS_ABILITY
	cp SNIPER
	jr nz, .no_sniper
	ld [hl], 3
.no_sniper
	ld b, $4
	call Divide

.no_crit
; Item boosts
	call GetUserItem

	ld a, b
	and a
	jr z, .DoneItem

	ld hl, TypeBoostItems

.NextItem:
	ld a, [hli]
	cp $ff
	jr z, .DoneItem

; Item effect
	cp b
	ld a, [hli]
	jr nz, .NextItem

	cp PHYSICAL
	jr z, .CategoryBoost
	cp SPECIAL
	jr z, .CategoryBoost

; Type
	ld b, a
	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVar
	cp b
	jr nz, .DoneItem
	jr .ApplyBoost

.CategoryBoost
	ld b, a
	ld a, BATTLE_VARS_MOVE_CATEGORY
	call GetBattleVar
	cp b
	jr nz, .DoneItem

.ApplyBoost
; * 100 + item effect amount
	ld a, c
	add 100
	ld [hMultiplier], a
	call Multiply

; / 100
	ld a, 100
	ld [hDivisor], a
	ld b, 4
	call Divide
.DoneItem:
; If we exceed $ffff at this point, skip to capping to 997 as the
; final damage.
	ld a, [hQuotient]
	and a
	jr nz, .Cap

; Update CurDamage (capped at 997).
	ld hl, CurDamage
	ld b, [hl]
	ld a, [hQuotient + 2]
	add b
	ld [hQuotient + 2], a
	jr nc, .dont_cap_1

	ld a, [hQuotient + 1]
	inc a
	ld [hQuotient + 1], a
	and a
	jr z, .Cap

.dont_cap_1
	ld a, [hQuotient + 1]
	cp 998 / $100
	jr c, .dont_cap_2

	cp 998 / $100 + 1
	jr nc, .Cap

	ld a, [hQuotient + 2]
	cp 998 % $100
	jr nc, .Cap

.dont_cap_2
	inc hl

	ld a, [hQuotient + 2]
	ld b, [hl]
	add b
	ld [hld], a

	ld a, [hQuotient + 1]
	ld b, [hl]
	adc b
	ld [hl], a
	jr c, .Cap

	ld a, [hl]
	cp 998 / $100
	jr c, .dont_cap_3

	cp 998 / $100 + 1
	jr nc, .Cap

	inc hl
	ld a, [hld]
	cp 998 % $100
	jr c, .dont_cap_3

.Cap:
	ld a, 997 / $100
	ld [hli], a
	ld a, 997 % $100
	ld [hld], a


.dont_cap_3
; Minimum neutral damage is 2 (bringing the cap to 999).
	inc hl
	ld a, [hl]
	add 2
	ld [hld], a
	jr nc, .dont_floor
	inc [hl]
.dont_floor

	ld a, 1
	and a
	ret

TypeBoostItems: ; 35703
	db HELD_NORMAL_BOOST,   NORMAL   ; Silk Scarf
	db HELD_FIGHTING_BOOST, FIGHTING ; Black Belt
	db HELD_FLYING_BOOST,   FLYING   ; Sharp Beak
	db HELD_POISON_BOOST,   POISON   ; Poison Barb
	db HELD_GROUND_BOOST,   GROUND   ; Soft Sand
	db HELD_ROCK_BOOST,     ROCK     ; Hard Stone
	db HELD_BUG_BOOST,      BUG      ; SilverPowder
	db HELD_GHOST_BOOST,    GHOST    ; Spell Tag
	db HELD_FIRE_BOOST,     FIRE     ; Charcoal
	db HELD_WATER_BOOST,    WATER    ; Mystic Water
	db HELD_GRASS_BOOST,    GRASS    ; Miracle Seed
	db HELD_ELECTRIC_BOOST, ELECTRIC ; Magnet
	db HELD_PSYCHIC_BOOST,  PSYCHIC  ; TwistedSpoon
	db HELD_ICE_BOOST,      ICE      ; NeverMeltIce
	db HELD_DRAGON_BOOST,   DRAGON   ; Dragon Scale
	db HELD_DARK_BOOST,     DARK     ; BlackGlasses
	db HELD_STEEL_BOOST,    STEEL    ; Metal Coat
	db HELD_FAIRY_BOOST,    FAIRY    ; Pink Bow
	db HELD_PHYSICAL_BOOST, PHYSICAL ; Muscle Band
	db HELD_SPECIAL_BOOST,  SPECIAL  ; Wise Glasses
	db $ff
; 35726


BattleCommand_ConstantDamage: ; 35726
; constantdamage

	ld hl, BattleMonLevel
	ld a, [hBattleTurn]
	and a
	jr z, .got_turn
	ld hl, EnemyMonLevel

.got_turn
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_LEVEL_DAMAGE
	ld b, [hl]
	ld a, 0 ; not xor a; preserve carry flag
	jr z, .got_power

	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_PSYWAVE
	jr z, .psywave

	cp EFFECT_SUPER_FANG
	jr z, .super_fang

	cp EFFECT_REVERSAL
	jr z, .reversal

	ld a, BATTLE_VARS_MOVE_POWER
	call GetBattleVar
	ld b, a
	xor a
	jr .got_power

.psywave
	ld a, b
	srl a
	add b
	ld b, a
.psywave_loop
	call BattleRandom
	and a
	jr z, .psywave_loop
	cp b
	jr nc, .psywave_loop
	ld b, a
	xor a
	jr .got_power

.super_fang
	ld hl, EnemyMonHP
	ld a, [hBattleTurn]
	and a
	jr z, .got_hp
	ld hl, BattleMonHP
.got_hp
	ld a, [hli]
	srl a
	ld b, a
	ld a, [hl]
	rr a
	push af
	ld a, b
	pop bc
	and a
	jr nz, .got_power
	or b
	ld a, 0 ; not xor a; preserve carry flag?
	jr nz, .got_power
	ld b, $1
	jr .got_power

.got_power
	ld hl, CurDamage
	ld [hli], a
	ld [hl], b
	ret

.reversal
	ld hl, BattleMonHP
	ld a, [hBattleTurn]
	and a
	jr z, .reversal_got_hp
	ld hl, EnemyMonHP
.reversal_got_hp
	xor a
	ld [hDividend], a
	ld [hMultiplicand + 0], a
	ld a, [hli]
	ld [hMultiplicand + 1], a
	ld a, [hli]
	ld [hMultiplicand + 2], a
	ld a, $30
	ld [hMultiplier], a
	call Multiply
	ld a, [hli]
	ld b, a
	ld a, [hl]
	ld [hDivisor], a
	ld a, b
	and a
	jr z, .skip_to_divide

	ld a, [hProduct + 4]
	srl b
	rr a
	srl b
	rr a
	ld [hDivisor], a
	ld a, [hProduct + 2]
	ld b, a
	srl b
	ld a, [hProduct + 3]
	rr a
	srl b
	rr a
	ld [hDividend + 3], a
	ld a, b
	ld [hDividend + 2], a

.skip_to_divide
	ld b, $4
	call Divide
	ld a, [hQuotient + 2]
	ld b, a
	ld hl, .FlailPower

.reversal_loop
	ld a, [hli]
	cp b
	jr nc, .break_loop
	inc hl
	jr .reversal_loop

.break_loop
	ld a, [hBattleTurn]
	and a
	ld a, [hl]
	jr nz, .notPlayersTurn

	ld hl, wPlayerMoveStructPower
	ld [hl], a
	push hl
	call PlayerAttackDamage
	jr .notEnemysTurn

.notPlayersTurn
	ld hl, wEnemyMoveStructPower
	ld [hl], a
	push hl
	call EnemyAttackDamage

.notEnemysTurn
	call BattleCommand_DamageCalc
	pop hl
	ld [hl], 1
	ret

.FlailPower:
	;  px,  bp
	db  1, 200
	db  4, 150
	db  9, 100
	db 16,  80
	db 32,  40
	db 48,  20
; 35813


BattleCommand_Counter:
	ld b, EFFECT_COUNTER
	ld c, PHYSICAL
	jr BattleCommand_Counterattack
BattleCommand_MirrorCoat:
	ld b, EFFECT_MIRROR_COAT
	ld c, SPECIAL
BattleCommand_Counterattack:
	ld a, 1
	ld [AttackMissed], a
	ld a, BATTLE_VARS_LAST_COUNTER_MOVE_OPP
	call GetBattleVar
	and a
	ret z

	push bc
	ld b, a
	farcall GetMoveEffect
	ld a, b
	pop bc
	cp b
	ret z

	call BattleCommand_ResetTypeMatchup
	ld a, [wTypeMatchup]
	and a
	ret z

	call CheckOpponentWentFirst
	ret z

	push bc
	ld a, BATTLE_VARS_LAST_COUNTER_MOVE_OPP
	call GetBattleVar
	dec a
	ld de, StringBuffer1
	call GetMoveData
	pop bc

	ld a, [StringBuffer1 + MOVE_POWER]
	and a
	ret z

	ld a, [StringBuffer1 + MOVE_CATEGORY]
	cp c
	ret nz

	ld hl, CurDamage
	ld a, [hli]
	or [hl]
	ret z

	ld a, [hl]
	add a
	ld [hld], a
	ld a, [hl]
	adc a
	ld [hl], a
	jr nc, .capped
	ld a, $ff
	ld [hli], a
	ld [hl], a
.capped

	xor a
	ld [AttackMissed], a
	ret


BattleCommand_Encore: ; 35864
; encore

	ld hl, EnemyMonMoves
	ld de, EnemyEncoreCount
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld hl, BattleMonMoves
	ld de, PlayerEncoreCount
.ok
	ld a, BATTLE_VARS_LAST_MOVE_OPP
	call GetBattleVar
	and a
	jp z, .failed
	cp STRUGGLE
	jp z, .failed
	cp ENCORE
	jp z, .failed
	ld b, a

.got_move
	ld a, [hli]
	cp b
	jr nz, .got_move

	ld bc, BattleMonPP - BattleMonMoves - 1
	add hl, bc
	ld a, [hl]
	and $3f
	jp z, .failed
	ld a, [AttackMissed]
	and a
	jp nz, .failed
	ld a, BATTLE_VARS_SUBSTATUS2_OPP
	call GetBattleVarAddr
	bit SUBSTATUS_ENCORED, [hl]
	jp nz, .failed
	set SUBSTATUS_ENCORED, [hl]
	call BattleRandom
	and $3
rept 3
	inc a
endr
	ld [de], a
	call CheckOpponentWentFirst
	jr nz, .finish_move
	ld a, [hBattleTurn]
	and a
	jr z, .force_last_enemy_move

	push hl
	ld a, [LastPlayerMove]
	ld b, a
	ld c, 0
	ld hl, BattleMonMoves
.find_player_move
	ld a, [hli]
	cp b
	jr z, .got_player_move
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .find_player_move
	pop hl
	res SUBSTATUS_ENCORED, [hl]
	xor a
	ld [de], a
	jr .failed

.got_player_move
	pop hl
	ld a, c
	ld [CurMoveNum], a
	ld a, b
	ld [CurPlayerMove], a
	dec a
	ld de, wPlayerMoveStruct
	call GetMoveData
	jr .finish_move

.force_last_enemy_move
	push hl
	ld a, [LastEnemyMove]
	ld b, a
	ld c, 0
	ld hl, EnemyMonMoves
.find_enemy_move
	ld a, [hli]
	cp b
	jr z, .got_enemy_move
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .find_enemy_move
	pop hl
	res SUBSTATUS_ENCORED, [hl]
	xor a
	ld [de], a
	jr .failed

.got_enemy_move
	pop hl
	ld a, c
	ld [CurEnemyMoveNum], a
	ld a, b
	ld [CurEnemyMove], a
	dec a
	ld de, wEnemyMoveStruct
	call GetMoveData

.finish_move
	call AnimateCurrentMove
	ld hl, GotAnEncoreText
	jp StdBattleTextBox

.failed
	jp PrintDidntAffect2

; 35926


BattleCommand_PainSplit: ; 35926
; painsplit

	ld a, [AttackMissed]
	and a
	jp nz, .ButItFailed
	call CheckSubstituteOpp
	jp nz, .ButItFailed
	call AnimateCurrentMove
	ld hl, BattleMonMaxHP + 1
	ld de, EnemyMonMaxHP + 1
	call .PlayerShareHP
	ld a, $1
	ld [wWhichHPBar], a
	hlcoord 11, 9
	predef AnimateHPBar
	ld hl, EnemyMonHP
	ld a, [hli]
	ld [Buffer4], a
	ld a, [hli]
	ld [Buffer3], a
	ld a, [hli]
	ld [Buffer2], a
	ld a, [hl]
	ld [Buffer1], a
	call .EnemyShareHP
	xor a
	ld [wWhichHPBar], a
	call ResetDamage
	hlcoord 1, 2
	predef AnimateHPBar
	farcall _UpdateBattleHUDs

	ld hl, SharedPainText
	jp StdBattleTextBox

.PlayerShareHP:
	ld a, [hld]
	ld [Buffer1], a
	ld a, [hld]
	ld [Buffer2], a
	ld a, [hld]
	ld b, a
	ld [Buffer3], a
	ld a, [hl]
	ld [Buffer4], a
	dec de
	dec de
	ld a, [de]
	dec de
	add b
	ld [CurDamage + 1], a
	ld b, [hl]
	ld a, [de]
	adc b
	srl a
	ld [CurDamage], a
	ld a, [CurDamage + 1]
	rr a
	ld [CurDamage + 1], a
rept 3
	inc hl
endr
rept 3
	inc de
endr

.EnemyShareHP: ; 359ac
	ld c, [hl]
	dec hl
	ld a, [CurDamage + 1]
	sub c
	ld b, [hl]
	dec hl
	ld a, [CurDamage]
	sbc b
	jr nc, .skip

	ld a, [CurDamage]
	ld b, a
	ld a, [CurDamage + 1]
	ld c, a
.skip
	ld a, c
	ld [hld], a
	ld [Buffer5], a
	ld a, b
	ld [hli], a
	ld [Buffer6], a
	ret

; 359cd

.ButItFailed:
	jp PrintDidntAffect2

; 359d0


BattleCommand_LockOn: ; 35a53
; lockon

	call CheckSubstituteOpp
	jr nz, .fail

	ld a, [AttackMissed]
	and a
	jr nz, .fail

	ld a, BATTLE_VARS_SUBSTATUS2_OPP
	call GetBattleVarAddr
	set SUBSTATUS_LOCK_ON, [hl]
	call AnimateCurrentMove

	ld hl, TookAimText
	jp StdBattleTextBox

.fail
	call AnimateFailedMove
	jp PrintDidntAffect

; 35a74


BattleCommand_Sketch: ; 35a74
; sketch

	call ClearLastMove
; Don't sketch during a link battle
	ld a, [wLinkMode]
	and a
	jr z, .not_linked
	call AnimateFailedMove
	jp PrintNothingHappened

.not_linked
; If the opponent has a substitute up, fail.
	call CheckSubstituteOpp
	jp nz, .fail
; If the opponent is transformed, fail.
	ld a, BATTLE_VARS_SUBSTATUS2_OPP
	call GetBattleVarAddr
	bit SUBSTATUS_TRANSFORMED, [hl]
	jp nz, .fail
; If the user is transformed, fail.
	ld a, BATTLE_VARS_SUBSTATUS2
	call GetBattleVarAddr
	bit SUBSTATUS_TRANSFORMED, [hl]
	jp nz, .fail
; Get the user's moveset in its party struct.
; This move replacement shall be permanent.
; Pointer will be in de.
	ld a, MON_MOVES
	call UserPartyAttr
	ld d, h
	ld e, l
; Get the battle move structs.
	ld hl, BattleMonMoves
	ld a, [hBattleTurn]
	and a
	jr z, .get_last_move
	ld hl, EnemyMonMoves
.get_last_move
	ld a, BATTLE_VARS_LAST_COUNTER_MOVE_OPP
	call GetBattleVar
	ld [wTypeMatchup], a
	ld b, a
; Fail if move is invalid or is Struggle.
	and a
	jr z, .fail
	cp STRUGGLE
	jr z, .fail
; Fail if user already knows that move
	ld c, NUM_MOVES
.does_user_already_know_move
	ld a, [hli]
	cp b
	jr z, .fail
	dec c
	jr nz, .does_user_already_know_move
; Find Sketch in the user's moveset.
; Pointer in hl, and index in c.
	dec hl
	ld c, NUM_MOVES
.find_sketch
	dec c
	ld a, [hld]
	cp SKETCH
	jr nz, .find_sketch
	inc hl
; The Sketched move is loaded to that slot.
	ld a, b
	ld [hl], a
; Copy the base PP from that move.
	push bc
	push hl
	dec a
	ld hl, Moves + MOVE_PP
	call GetMoveAttr
	pop hl
	ld bc, BattleMonPP - BattleMonMoves
	add hl, bc
	ld [hl], a
	pop bc

	ld a, [hBattleTurn]
	and a
	jr z, .user_trainer
	ld a, [wBattleMode]
	dec a
	jr nz, .user_trainer
; wildmon
	ld a, [hl]
	push bc
	ld hl, wWildMonPP
	ld b, 0
	add hl, bc
	ld [hl], a
	ld hl, wWildMonMoves
	add hl, bc
	pop bc
	ld [hl], b
	jr .done_copy

.user_trainer
	ld a, [hl]
	push af
	ld l, c
	ld h, 0
	add hl, de
	ld a, b
	ld [hl], a
	pop af
	ld de, MON_PP - MON_MOVES
	add hl, de
	ld [hl], a
.done_copy
	call GetMoveName
	call AnimateCurrentMove

	ld hl, SketchedText
	jp StdBattleTextBox

.fail
	call AnimateFailedMove
	jp PrintDidntAffect

; 35b16


BattleCommand_SleepTalk: ; 35b33
; sleeptalk

	call ClearLastMove
	ld a, [AttackMissed]
	and a
	jr nz, .fail
	ld a, [hBattleTurn]
	and a
	ld hl, BattleMonMoves + 1
	ld a, [DisabledMove]
	ld d, a
	jr z, .got_moves
	ld hl, EnemyMonMoves + 1
	ld a, [EnemyDisabledMove]
	ld d, a
.got_moves
	ld a, BATTLE_VARS_STATUS
	call GetBattleVar
	and SLP
	jr z, .fail
	ld a, [hl]
	and a
	jr z, .fail
	call .safely_check_has_usable_move
	jr c, .fail
	dec hl
.sample_move
	push hl
	call BattleRandom
	and %11 ; NUM_MOVES - 1
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	pop hl
	and a
	jr z, .sample_move
	ld e, a
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	cp e
	jr z, .sample_move
	ld a, e
	cp d
	jr z, .sample_move
	call .check_two_turn_move
	jr z, .sample_move
	ld a, BATTLE_VARS_MOVE
	call GetBattleVarAddr
	ld a, e
	ld [hl], a
	call CheckUserIsCharging
	jr nz, .charging
	ld a, [wKickCounter]
	push af
	call BattleCommand_LowerSub
	pop af
	ld [wKickCounter], a
.charging
	call LoadMoveAnim
	call UpdateMoveData
	jp ResetTurn

.fail
	call AnimateFailedMove
	jp TryPrintButItFailed

.safely_check_has_usable_move
	push hl
	push de
	push bc
	call .check_has_usable_move
	pop bc
	pop de
	pop hl
	ret

.check_has_usable_move
	ld a, [hBattleTurn]
	and a
	ld a, [DisabledMove]
	jr z, .got_move_2

	ld a, [EnemyDisabledMove]
.got_move_2
	ld b, a
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	ld c, a
	dec hl
	ld d, NUM_MOVES
.loop2
	ld a, [hl]
	and a
	jr z, .carry

	cp c
	jr z, .nope
	cp b
	jr z, .nope

	call .check_two_turn_move
	jr nz, .no_carry

.nope
	inc hl
	dec d
	jr nz, .loop2

.carry
	scf
	ret

.no_carry
	and a
	ret

.check_two_turn_move
	push hl
	push de
	push bc

	ld b, a
	farcall GetMoveEffect
	ld a, b

	pop bc
	pop de
	pop hl

	cp EFFECT_SKULL_BASH
	ret z
	cp EFFECT_RAZOR_WIND
	ret z
	cp EFFECT_SKY_ATTACK
	ret z
	cp EFFECT_SOLAR_BEAM
	ret z
	cp EFFECT_FLY
	ret z
	cp EFFECT_BIDE
	ret

; 35bff


BattleCommand_DestinyBond: ; 35bff
; destinybond

	ld a, BATTLE_VARS_SUBSTATUS2
	call GetBattleVarAddr
	set SUBSTATUS_DESTINY_BOND, [hl]
	call AnimateCurrentMove
	ld hl, DestinyBondEffectText
	jp StdBattleTextBox

; 35c0f


BattleCommand_FalseSwipe: ; 35c94
; falseswipe

	ld hl, EnemyMonHP
	ld a, [hBattleTurn]
	and a
	jr z, .got_hp
	ld hl, BattleMonHP
.got_hp
	ld de, CurDamage
	ld c, 2
	push hl
	push de
	call StringCmp
	pop de
	pop hl
	jr c, .done
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	dec a
	ld [de], a
	inc a
	jr nz, .okay
	dec de
	ld a, [de]
	dec a
	ld [de], a
.okay
	ld a, [CriticalHit]
	cp $2
	jr nz, .carry
	xor a
	ld [CriticalHit], a
.carry
	scf
	ret

.done
	and a
	ret

; 35cc9


BattleCommand_HealBell: ; 35cc9
; healbell

	ld de, PartyMon1Status
	ld a, [hBattleTurn]
	and a
	jr z, .got_status
	ld de, OTPartyMon1Status
.got_status
	ld a, BATTLE_VARS_STATUS
	call GetBattleVarAddr
	xor a
	ld [hl], a
	ld h, d
	ld l, e
	ld bc, PARTYMON_STRUCT_LENGTH
	ld d, PARTY_LENGTH
.loop
	ld [hl], a
	add hl, bc
	dec d
	jr nz, .loop
	call AnimateCurrentMove

	ld hl, BellChimedText
	jp StdBattleTextBox


FarPlayBattleAnimation: ; 35d00
; play animation de

	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVar
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	ret nz

	; fallthrough
; 35d08

PlayFXAnimID: ; 35d08
	ld a, e
	ld [FXAnimIDLo], a
	ld a, d
	ld [FXAnimIDHi], a

	ld c, 3
	call DelayFrames

	farcall PlayBattleAnim

	ret

; 35d1c


EnemyHurtItself: ; 35d1c
	ld hl, CurDamage
	ld a, [hli]
	ld b, a
	ld a, [hl]
	or b
	jr z, .did_no_damage

	ld a, c
	and a
	jr nz, .mimic_sub_check

	ld a, [EnemySubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jp nz, SelfInflictDamageToSubstitute

.mimic_sub_check
	ld a, [hld]
	ld b, a
	ld a, [EnemyMonHP + 1]
	ld [Buffer3], a
	sub b
	ld [EnemyMonHP + 1], a
	ld a, [hl]
	ld b, a
	ld a, [EnemyMonHP]
	ld [Buffer4], a
	sbc b
	ld [EnemyMonHP], a
	jr nc, .mimic_faint

	ld a, [Buffer4]
	ld [hli], a
	ld a, [Buffer3]
	ld [hl], a

	xor a
	ld hl, EnemyMonHP
	ld [hli], a
	ld [hl], a

.mimic_faint
	ld hl, EnemyMonMaxHP
	ld a, [hli]
	ld [Buffer2], a
	ld a, [hl]
	ld [Buffer1], a
	ld hl, EnemyMonHP
	ld a, [hli]
	ld [Buffer6], a
	ld a, [hl]
	ld [Buffer5], a
	hlcoord 1, 2
	xor a
	ld [wWhichHPBar], a
	predef AnimateHPBar
.did_no_damage
	jp RefreshBattleHuds

; 35d7e


PlayerHurtItself: ; 35d7e
	ld hl, CurDamage
	ld a, [hli]
	ld b, a
	ld a, [hl]
	or b
	jr z, .did_no_damage

	ld a, c
	and a
	jr nz, .mimic_sub_check

	ld a, [PlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jp nz, SelfInflictDamageToSubstitute
.mimic_sub_check
	ld a, [hld]
	ld b, a
	ld a, [BattleMonHP + 1]
	ld [Buffer3], a
	sub b
	ld [BattleMonHP + 1], a
	ld [Buffer5], a
	ld b, [hl]
	ld a, [BattleMonHP]
	ld [Buffer4], a
	sbc b
	ld [BattleMonHP], a
	ld [Buffer6], a
	jr nc, .mimic_faint

	ld a, [Buffer4]
	ld [hli], a
	ld a, [Buffer3]
	ld [hl], a
	xor a

	ld hl, BattleMonHP
	ld [hli], a
	ld [hl], a
	ld hl, Buffer5
	ld [hli], a
	ld [hl], a

.mimic_faint
	ld hl, BattleMonMaxHP
	ld a, [hli]
	ld [Buffer2], a
	ld a, [hl]
	ld [Buffer1], a
	hlcoord 11, 9
	ld a, $1
	ld [wWhichHPBar], a
	predef AnimateHPBar
.did_no_damage
	jp RefreshBattleHuds

; 35de0


SelfInflictDamageToSubstitute: ; 35de0

	ld hl, SubTookDamageText
	call StdBattleTextBox

	ld de, EnemySubstituteHP
	ld a, [hBattleTurn]
	and a
	jr z, .got_hp
	ld de, PlayerSubstituteHP
.got_hp

	ld hl, CurDamage
	ld a, [hli]
	and a
	jr nz, .broke

	ld a, [de]
	sub [hl]
	ld [de], a
	jr z, .broke
	jr nc, .done

.broke
	ld a, BATTLE_VARS_SUBSTATUS4_OPP
	call GetBattleVarAddr
	res SUBSTATUS_SUBSTITUTE, [hl]

	ld hl, SubFadedText
	call StdBattleTextBox

	call SwitchTurn
	call BattleCommand_LowerSubNoAnim
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVar
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	call z, AppearUserLowerSub
	call SwitchTurn

	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVarAddr
	cp EFFECT_MULTI_HIT
	jr z, .ok
	cp EFFECT_DOUBLE_HIT
	jr z, .ok
	cp EFFECT_TRIPLE_KICK
	jr z, .ok
	xor a
	ld [hl], a
.ok
	call RefreshBattleHuds
.done
	jp ResetDamage

; 35e40


UpdateMoveData: ; 35e40

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVarAddr
	ld d, h
	ld e, l

	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	ld [CurMove], a
	ld [wNamedObjectIndexBuffer], a

	dec a
	call GetMoveData
	call GetMoveName
	jp CopyName1

; 35e5c

IsLeafGuardActive:
; returns z if leaf guard applies for enemy
	call GetOpponentAbilityAfterMoldBreaker
	cp LEAF_GUARD
	ret nz
	call GetWeatherAfterCloudNine
	cp WEATHER_SUN
	ret

PostStatusWithSynchronize:
	farcall RunEnemySynchronizeAbility
PostStatus:
	farcall UseEnemyHeldStatusHealingItem
	farcall RunEnemyStatusHealAbilities
	ret

BattleCommand_SleepTarget: ; 35e5c
; sleeptarget

	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_SLEEP
	jr nz, .not_protected_by_item

	ld a, [hl]
	ld [wNamedObjectIndexBuffer], a
	call GetItemName
	ld hl, ProtectedByText
	jr .fail

.not_protected_by_item
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	ld d, h
	ld e, l
	ld a, [de]
	and SLP
	ld hl, AlreadyAsleepText
	jr nz, .fail

	ld a, [AttackMissed]
	and a
	jp nz, PrintDidntAffect2

	call GetOpponentAbilityAfterMoldBreaker
	cp INSOMNIA
	jr z, .ability_ok
	cp VITAL_SPIRIT
	jr z, .ability_ok
	call IsLeafGuardActive
	jr z, .ability_ok
	ld a, [de]
	and a
	jr nz, .fail

	call CheckSubstituteOpp
	jr nz, .fail

	call AnimateCurrentMove

.random_loop
	call BattleRandom
	and %11
	jr z, .random_loop
	inc a
	ld [de], a
	call UpdateOpponentInParty
	call RefreshBattleHuds

	ld hl, FellAsleepText
	call StdBattleTextBox

	call PostStatus
	ld a, BATTLE_VARS_STATUS_OPP
	cp 1 << SLP
	jp z, OpponentCantMove
	ret

.ability_ok
	farcall ShowEnemyAbilityActivation
	jp PrintDidntAffect2

.fail
	push hl
	call AnimateFailedMove
	pop hl
	jp StdBattleTextBox

; 35ece


BattleCommand_PoisonTarget: ; 35eee
; poisontarget

	call CheckSubstituteOpp
	ret nz
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	and a
	ret nz
	ld a, [TypeModifier]
	and a
	ret z
	call CheckIfTargetIsPoisonType
	ret z
	call CheckIfTargetIsSteelType
	ret z
	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_POISON
	ret z
	call GetOpponentAbilityAfterMoldBreaker
	cp IMMUNITY
	ret z
	call IsLeafGuardActive
	ret z
	ld a, [EffectFailed]
	and a
	ret nz
	call SafeCheckSafeguard
	ret nz

	call PoisonOpponent
	ld de, ANIM_PSN
	call PlayOpponentBattleAnim
	call RefreshBattleHuds

	ld hl, WasPoisonedText
	call StdBattleTextBox

	jp PostStatusWithSynchronize


BattleCommand_Poison: ; 35f2c
; poison

	ld hl, DoesntAffectText
	ld a, [TypeModifier]
	and a
	jp z, .failed
	call GetOpponentAbilityAfterMoldBreaker
	cp IMMUNITY
	jp z, .ability_ok
	call IsLeafGuardActive
	jr z, .ability_ok
	call CheckIfTargetIsPoisonType
	jp z, .failed
	call CheckIfTargetIsSteelType
	jp z, .failed

	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVar
	ld b, a
	ld hl, AlreadyPoisonedText
	and 1 << PSN
	jp nz, .failed

	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_POISON
	jr nz, .do_poison
	ld a, [hl]
	ld [wNamedObjectIndexBuffer], a
	call GetItemName
	ld hl, ProtectedByText
	jr .failed

.do_poison
	ld hl, DidntAffect1Text
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVar
	and a
	jr nz, .failed

	ld a, [hBattleTurn]
	and a
	jr z, .mimic_random

	ld a, [wLinkMode]
	and a
	jr nz, .mimic_random

	ld a, [InBattleTowerBattle]
	and a
	jr nz, .mimic_random

	ld a, [PlayerSubStatus2]
	bit SUBSTATUS_LOCK_ON, a
	jr nz, .mimic_random

.mimic_random
	call CheckSubstituteOpp
	jr nz, .failed
	ld a, [AttackMissed]
	and a
	jr nz, .failed
	call .check_toxic
	jr z, .toxic

	call .apply_poison
	ld hl, WasPoisonedText
	call StdBattleTextBox
	jr .finished

.toxic
	set SUBSTATUS_TOXIC, [hl]
	xor a
	ld [de], a
	call .apply_poison

	ld hl, BadlyPoisonedText
	call StdBattleTextBox

.finished
	jp PostStatusWithSynchronize

.ability_ok
	farcall ShowEnemyAbilityActivation
	ld hl, DoesntAffectText
.failed
	push hl
	call AnimateFailedMove
	pop hl
	jp StdBattleTextBox

; 35fc0


.apply_poison ; 35fc0
	call AnimateCurrentMove
	call PoisonOpponent
	jp RefreshBattleHuds

; 35fc9


.check_toxic ; 35fc9
	ld a, BATTLE_VARS_SUBSTATUS2_OPP
	call GetBattleVarAddr
	ld a, [hBattleTurn]
	and a
	ld de, EnemyToxicCount
	jr z, .ok
	ld de, PlayerToxicCount
.ok
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_TOXIC
	ret

; 35fe1


PoisonOpponent: ; 35ff5
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	set PSN, [hl]
	jp UpdateOpponentInParty

; 35fff


BattleCommand_DrainTarget: ; 35fff
; draintarget
	call SapHealth
	ld hl, SuckedHealthText
	jp StdBattleTextBox

; 36008


BattleCommand_EatDream: ; 36008
; eatdream
	call SapHealth
	ld hl, DreamEatenText
	jp StdBattleTextBox

; 36011


SapHealth: ; 36011
	; Don't do anything if HP is full
	farcall CheckFullHP_b
	ld a, b
	and a
	ret z

	; get damage
	ld hl, CurDamage
	ld a, [hli]
	ld b, a
	ld c, [hl]

	; halve result
	srl b
	rr c

	; for Drain Kiss, we want 75% drain instead of 50%
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	cp DRAIN_KISS
	jr nz, .skip_drain_kiss
	ld h, b
	ld l, c
	srl b
	rr c
	add hl, bc
	ld b, h
	ld c, l

.skip_drain_kiss
	; ensure minimum 1HP drained
	ld a, b
	and a
	jr nz, .skip_increase
	ld a, c
	and a
	jr nz, .skip_increase
	ld c, 1
.skip_increase
	; check for Liquid Ooze
	push bc
	call GetOpponentAbilityAfterMoldBreaker
	pop bc
	cp LIQUID_OOZE
	jr z, .damage
	farcall RestoreHP
	ret
.damage
	farcall ShowEnemyAbilityActivation
	farcall SubtractHPFromUser
	ret


BattleCommand_BurnTarget: ; 3608c
; burntarget

	xor a
	ld [wNumHits], a
	call CheckSubstituteOpp
	ret nz
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	and a
	jp nz, Defrost
	ld a, [TypeModifier]
	and a
	ret z
	call CheckIfTargetIsFireType
	ret z
	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_BURN
	ret z
	call GetOpponentAbilityAfterMoldBreaker
	cp WATER_VEIL
	ret z
	call IsLeafGuardActive
	ret z
	ld a, [EffectFailed]
	and a
	ret nz
	call SafeCheckSafeguard
	ret nz
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	set BRN, [hl]
	call UpdateOpponentInParty
	ld de, ANIM_BRN
	call PlayOpponentBattleAnim
	call RefreshBattleHuds

	ld hl, WasBurnedText
	call StdBattleTextBox

	jp PostStatusWithSynchronize

; 360dd


Defrost: ; 360dd
	ld a, [hl]
	and 1 << FRZ
	ret z

	xor a
	ld [hl], a

	ld a, [hBattleTurn]
	and a
	ld a, [CurOTMon]
	ld hl, OTPartyMon1Status
	jr z, .ok
	ld hl, PartyMon1Status
	ld a, [CurBattleMon]
.ok

	call GetPartyLocation
	xor a
	ld [hl], a
	call UpdateOpponentInParty

	ld hl, DefrostedOpponentText
	jp StdBattleTextBox

; 36102


BattleCommand_FreezeTarget: ; 36102
; freezetarget

	xor a
	ld [wNumHits], a
	call CheckSubstituteOpp
	ret nz
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	and a
	ret nz
	ld a, [TypeModifier]
	and a
	ret z
	call GetWeatherAfterCloudNine
	cp WEATHER_SUN
	ret z
	call CheckIfTargetIsIceType
	ret z
	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_FREEZE
	ret z
	call GetOpponentAbilityAfterMoldBreaker
	cp MAGMA_ARMOR
	ret z
	call IsLeafGuardActive
	ret z
	ld a, [EffectFailed]
	and a
	ret nz
	call SafeCheckSafeguard
	ret nz
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	set FRZ, [hl]
	call UpdateOpponentInParty
	ld de, ANIM_FRZ
	call PlayOpponentBattleAnim
	call RefreshBattleHuds

	ld hl, WasFrozenText
	call StdBattleTextBox

	jp PostStatus
.no_magma_armor
	call OpponentCantMove
	call EndRechargeOpp
	ld hl, wEnemyJustGotFrozen
	ld a, [hBattleTurn]
	and a
	jr z, .finish
	ld hl, wPlayerJustGotFrozen
.finish
	ld [hl], $1
	ret

; 36165


BattleCommand_ParalyzeTarget: ; 36165
; paralyzetarget

	xor a
	ld [wNumHits], a
	call CheckSubstituteOpp
	ret nz
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	and a
	ret nz
	ld a, [TypeModifier]
	and a
	ret z
	call CheckIfTargetIsElectricType
	ret z
	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_PARALYZE
	ret z
	call GetOpponentAbilityAfterMoldBreaker
	cp LIMBER
	ret z
	call IsLeafGuardActive
	ret z
	ld a, [EffectFailed]
	and a
	ret nz
	call SafeCheckSafeguard
	ret nz
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	set PAR, [hl]
	call UpdateOpponentInParty
	ld de, ANIM_PAR
	call PlayOpponentBattleAnim
	call RefreshBattleHuds
	call PrintParalyze
	jp PostStatusWithSynchronize

; 361ac

BattleCommand_BulkUp:
	ld b, ATTACK
	ld c, DEFENSE
	jp BattleCommand_DoubleUp
BattleCommand_CalmMind:
	ld b, SP_ATTACK
	ld c, SP_DEFENSE
	jp BattleCommand_DoubleUp
BattleCommand_Growth:
	ld b, ATTACK
	ld c, SP_ATTACK
	call GetWeatherAfterCloudNine
	cp WEATHER_SUN
	jp nz, BattleCommand_DoubleUp
	ld b, $10 | ATTACK
	ld c, $10 | SP_ATTACK
	jp BattleCommand_DoubleUp
BattleCommand_DragonDance:
	ld b, ATTACK
	ld c, SPEED
	jp BattleCommand_DoubleUp
BattleCommand_HoneClaws:
	ld b, ATTACK
	ld c, ACCURACY
BattleCommand_DoubleUp:
; stats to raise are in bc
	push bc ; StatUp clobbers c (via CheckIfStatCanBeRaised), which we want to retain
	call ResetMiss
	call BattleCommand_StatUp
	ld a, [FailedMessage]
	ld d, a ; note for 2nd stat
	ld e, 0	; track if we've shown animation
	and a
	call z, .msg_animate
	pop bc
	ld b, c
	call ResetMiss
	call BattleCommand_StatUp
	ld a, [FailedMessage]
	and a
	jr z, .msg_animate
	and d ; if this result in a being nonzero, we want to give a failure message
	ret z
	ld b, MULTIPLE_STATS + 1
	call GetStatName
	call AnimateFailedMove
	ld hl, WontRiseAnymoreText
	jp StdBattleTextBox
.msg_animate
	ld a, e
	and a
	jp nz, BattleCommand_StatUpMessage
	ld a, 1
	ld [wKickCounter], a
	call AnimateCurrentMove
	jp BattleCommand_StatUpMessage

BattleCommand_AttackUp: ; 361ac
; attackup
	ld b, ATTACK
	jr BattleCommand_StatUp

BattleCommand_DefenseUp: ; 361b0
; defenseup
	ld b, DEFENSE
	jr BattleCommand_StatUp

BattleCommand_SpeedUp: ; 361b4
; speedup
	ld b, SPEED
	jr BattleCommand_StatUp

BattleCommand_SpecialAttackUp: ; 361b8
; specialattackup
	ld b, SP_ATTACK
	jr BattleCommand_StatUp

BattleCommand_SpecialDefenseUp: ; 361bc
; specialdefenseup
	ld b, SP_DEFENSE
	jr BattleCommand_StatUp

BattleCommand_AccuracyUp: ; 361c0
; accuracyup
	ld b, ACCURACY
	jr BattleCommand_StatUp

BattleCommand_EvasionUp: ; 361c4
; evasionup
	ld b, EVASION
	jr BattleCommand_StatUp

BattleCommand_AttackUp2: ; 361c8
; attackup2
	ld b, $10 | ATTACK
	jr BattleCommand_StatUp

BattleCommand_DefenseUp2: ; 361cc
; defenseup2
	ld b, $10 | DEFENSE
	jr BattleCommand_StatUp

BattleCommand_SpeedUp2: ; 361d0
; speedup2
	ld b, $10 | SPEED
	jr BattleCommand_StatUp

BattleCommand_SpecialAttackUp2: ; 361d4
; specialattackup2
	ld b, $10 | SP_ATTACK
	jr BattleCommand_StatUp

BattleCommand_SpecialDefenseUp2: ; 361d8
; specialdefenseup2
	ld b, $10 | SP_DEFENSE
	jr BattleCommand_StatUp

BattleCommand_AccuracyUp2: ; 361dc
; accuracyup2
	ld b, $10 | ACCURACY
	jr BattleCommand_StatUp

BattleCommand_EvasionUp2: ; 361e0
; evasionup2
	ld b, $10 | EVASION
	jr BattleCommand_StatUp

BattleCommand_StatUp: ; 361e4
; statup
	call CheckIfStatCanBeRaised
	ld a, [FailedMessage]
	and a
	ret nz
	jp StatUpAnimation

; 361ef


CheckIfStatCanBeRaised: ; 361ef
	ld a, b
	ld [LoweredStat], a
	ld hl, PlayerStatLevels
	ld a, [hBattleTurn]
	and a
	jr z, .got_stat_levels
	ld hl, EnemyStatLevels
.got_stat_levels
	ld a, [AttackMissed]
	and a
	jp nz, .stat_raise_failed
	ld a, [EffectFailed]
	and a
	jp nz, .stat_raise_failed
	ld a, [LoweredStat]
	and $f
	ld c, a
	ld b, 0
	add hl, bc
	ld b, [hl]
	inc b
	ld a, $d
	cp b
	jp c, .cant_raise_stat
	ld a, [LoweredStat]
	and $f0
	jr z, .got_num_stages
	inc b
	ld a, $d
	cp b
	jr nc, .got_num_stages
	ld b, a
.got_num_stages
	ld [hl], b
	push hl
	; Speed/Accuracy/Evasion doesn't mess with stats
	ld a, c
	cp ACCURACY
	jr nc, .done_calcing_stats
	cp SPEED
	jr z, .done_calcing_stats
	ld hl, BattleMonStats + 1
	ld de, PlayerStats
	ld a, [hBattleTurn]
	and a
	jr z, .got_stats_pointer
	ld hl, EnemyMonStats + 1
	ld de, EnemyStats
.got_stats_pointer
	push bc
	sla c
	ld b, 0
	add hl, bc
	ld a, c
	add e
	ld e, a
	jr nc, .no_carry
	inc d
.no_carry
	pop bc
	ld a, [hld]
	sub 999 % $100
	jr nz, .not_already_max
	ld a, [hl]
	sbc 999 / $100
	jp z, .stats_already_max
.not_already_max
	ld a, [hBattleTurn]
	and a
	jr z, .calc_player_stats
	call CalcEnemyStats
	jr .done_calcing_stats

.calc_player_stats
	call CalcPlayerStats
.done_calcing_stats
	pop hl
	xor a
	ld [FailedMessage], a
	ret

; 3626e


.stats_already_max ; 3626e
	pop hl
	dec [hl]
	; fallthrough
; 36270


.cant_raise_stat ; 36270
	ld a, $2
	ld [FailedMessage], a
	ld a, $1
	ld [AttackMissed], a
	ret

; 3627b


.stat_raise_failed ; 3627b
	ld a, $1
	ld [FailedMessage], a
	ret

; 36281


StatUpAnimation: ; 36281
	ld bc, wPlayerMinimized
	ld hl, DropPlayerSub
	ld a, [hBattleTurn]
	and a
	jr z, .do_player
	ld bc, wEnemyMinimized
	ld hl, DropEnemySub
.do_player
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	cp MINIMIZE
	ret nz

	ld a, $1
	ld [bc], a
	call _CheckBattleEffects
	ret nc

	xor a
	ld [hBGMapMode], a
	call CallBattleCore
	call WaitBGMap
	jp BattleCommand_MoveDelay

; 362ad


BattleCommand_AttackDown: ; 362ad
; attackdown
	ld a, ATTACK
	jr BattleCommand_StatDown

BattleCommand_DefenseDown: ; 362b1
; defensedown
	ld a, DEFENSE
	jr BattleCommand_StatDown

BattleCommand_SpeedDown: ; 362b5
; speeddown
	ld a, SPEED
	jr BattleCommand_StatDown

BattleCommand_SpecialAttackDown: ; 362b9
; specialattackdown
	ld a, SP_ATTACK
	jr BattleCommand_StatDown

BattleCommand_SpecialDefenseDown: ; 362bd
; specialdefensedown
	ld a, SP_DEFENSE
	jr BattleCommand_StatDown

BattleCommand_AccuracyDown: ; 362c1
; accuracydown
	ld a, ACCURACY
	jr BattleCommand_StatDown

BattleCommand_EvasionDown: ; 362c5
; evasiondown
	ld a, EVASION
	jr BattleCommand_StatDown

BattleCommand_AttackDown2: ; 362c9
; attackdown2
	ld a, $10 | ATTACK
	jr BattleCommand_StatDown

BattleCommand_DefenseDown2: ; 362cd
; defensedown2
	ld a, $10 | DEFENSE
	jr BattleCommand_StatDown

BattleCommand_SpeedDown2: ; 362d1
; speeddown2
	ld a, $10 | SPEED
	jr BattleCommand_StatDown

BattleCommand_SpecialAttackDown2: ; 362d5
; specialattackdown2
	ld a, $10 | SP_ATTACK
	jr BattleCommand_StatDown

BattleCommand_SpecialDefenseDown2: ; 362d9
; specialdefensedown2
	ld a, $10 | SP_DEFENSE
	jr BattleCommand_StatDown

BattleCommand_AccuracyDown2: ; 362dd
; accuracydown2
	ld a, $10 | ACCURACY
	jr BattleCommand_StatDown

BattleCommand_EvasionDown2: ; 362e1
; evasiondown2
	ld a, $10 | EVASION

BattleCommand_StatDown: ; 362e3
; statdown

	ld [LoweredStat], a

; check abilities
	and $f
	ld c, a
	call GetOpponentAbilityAfterMoldBreaker
	cp CLEAR_BODY
	jp z, .Failed
	cp HYPER_CUTTER
	jr z, .atk
	cp BIG_PECKS
	jr z, .def
	cp KEEN_EYE
	jr z, .acc
	jr .no_relevant_ability
.atk
	ld a, c
	cp ATTACK
	jr z, .Failed
.def
	ld a, c
	cp DEFENSE
	jr z, .Failed
.acc
	ld a, c
	cp ACCURACY
	jr z, .Failed

.no_relevant_ability
	call CheckMist
	jp nz, .Mist

	ld hl, EnemyStatLevels
	ld a, [hBattleTurn]
	and a
	jr z, .GetStatLevel
	ld hl, PlayerStatLevels

.GetStatLevel:
; Attempt to lower the stat.
	ld a, [LoweredStat]
	and $f
	ld c, a
	ld b, 0
	add hl, bc
	ld b, [hl]
	dec b
	jp z, .CantLower

; Sharply lower the stat if applicable.
	ld a, [LoweredStat]
	and $f0
	jr z, .ComputerMiss
	dec b
	jr nz, .ComputerMiss
	inc b

.ComputerMiss:
	call CheckSubstituteOpp
	jr nz, .Failed

	ld a, [AttackMissed]
	and a
	jr nz, .Failed

	ld a, [EffectFailed]
	and a
	jr nz, .Failed

	call CheckHiddenOpponent
	jr nz, .Failed

; Speed/Accuracy/Evasion reduction don't involve stats.
; TODO: make attack/defense stat changes not mess with stats either
	ld [hl], b
	ld a, c
	cp ACCURACY
	jr nc, .Hit
	cp SPEED
	jr z, .Hit

	push hl
	ld hl, EnemyMonAttack + 1
	ld de, EnemyStats
	ld a, [hBattleTurn]
	and a
	jr z, .do_enemy
	ld hl, BattleMonAttack + 1
	ld de, PlayerStats
.do_enemy
	call TryLowerStat
	pop hl
	jr z, .CouldntLower

.Hit:
	xor a
	ld [FailedMessage], a
	ret

.CouldntLower:
	inc [hl]
.CantLower:
	ld a, 3
	ld [FailedMessage], a
	ld a, 1
	ld [AttackMissed], a
	ret

.Failed:
	ld a, 1
	ld [FailedMessage], a
	ld [AttackMissed], a
	ret

.Mist:
	ld a, 2
	ld [FailedMessage], a
	ld a, 1
	ld [AttackMissed], a
	ret

; 36391


CheckMist: ; 36391
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_ATTACK_DOWN
	jr c, .dont_check_mist
	cp EFFECT_EVASION_DOWN + 1
	jr c, .check_mist
	cp EFFECT_ATTACK_DOWN_2
	jr c, .dont_check_mist
	cp EFFECT_EVASION_DOWN_2 + 1
	jr c, .check_mist
	cp EFFECT_ATTACK_DOWN_HIT
	jr c, .dont_check_mist
	cp EFFECT_EVASION_DOWN_HIT + 1
	jr c, .check_mist
.dont_check_mist
	xor a
	ret

.check_mist
	ld a, BATTLE_VARS_SUBSTATUS4_OPP
	call GetBattleVar
	bit SUBSTATUS_MIST, a
	ret

; 363b8


BattleCommand_StatUpMessage: ; 363b8
	ld a, [FailedMessage]
	and a
	ret nz
	ld a, [LoweredStat]
	and $f
	ld b, a
	inc b
	call GetStatName
	ld hl, .stat
	jp BattleTextBox

.stat
	text_jump UnknownText_0x1c0cc6
	start_asm
	ld hl, .up
	ld a, [LoweredStat]
	and $f0
	ret z
	ld hl, .wayup
	ret

.wayup
	text_jump UnknownText_0x1c0cd0
	db "@"

.up
	text_jump UnknownText_0x1c0ce0
	db "@"

; 363e9


BattleCommand_StatDownMessage: ; 363e9
	ld a, [FailedMessage]
	and a
	ret nz
	ld a, [LoweredStat]
	and $f
	ld b, a
	inc b
	call GetStatName
	ld hl, .stat
	call BattleTextBox
	; Competitive/Defiant activates here to give proper messages. A bit awkward,
	; but the alternative is to rewrite the stat-down logic.
	farcall RunEnemyStatIncreaseAbilities
	ret

.stat
	text_jump UnknownText_0x1c0ceb
	start_asm
	ld hl, .fell
	ld a, [LoweredStat]
	and $f0
	ret z
	ld hl, .sharplyfell
	ret

.sharplyfell
	text_jump UnknownText_0x1c0cf5
	db "@"
.fell
	text_jump UnknownText_0x1c0d06
	db "@"

; 3641a


TryLowerStat: ; 3641a
; Lower stat c from stat struct hl (buffer de).

	push bc
	sla c
	ld b, 0
	add hl, bc
	; add de, c
	ld a, c
	add e
	ld e, a
	jr nc, .no_carry
	inc d
.no_carry
	pop bc

; The lowest possible stat is 1.
	ld a, [hld]
	sub 1
	jr nz, .not_min
	ld a, [hl]
	and a
	ret z

.not_min
	ld a, [hBattleTurn]
	and a
	jr z, .Player

	call SwitchTurn
	call CalcPlayerStats
	call SwitchTurn
	jr .end

.Player:
	call SwitchTurn
	call CalcEnemyStats
	call SwitchTurn
.end
	ld a, 1
	and a
	ret

; 3644c


BattleCommand_StatUpFailText: ; 3644c
; statupfailtext
	ld a, [FailedMessage]
	and a
	ret z
	push af
	call BattleCommand_MoveDelay
	pop af
	dec a
	jp z, TryPrintButItFailed
	ld a, [LoweredStat]
	and $f
	ld b, a
	inc b
	call GetStatName
	ld hl, WontRiseAnymoreText
	jp StdBattleTextBox

; 3646a


BattleCommand_StatDownFailText: ; 3646a
; statdownfailtext
	ld a, [FailedMessage]
	and a
	ret z
	push af
	call BattleCommand_MoveDelay
	pop af
	dec a
	jp z, TryPrintButItFailed
	dec a
	ld hl, ProtectedByMistText
	jp z, StdBattleTextBox
	ld a, [LoweredStat]
	and $f
	ld b, a
	inc b
	call GetStatName
	ld hl, WontDropAnymoreText
	jp StdBattleTextBox

; 3648f


GetStatName: ; 3648f
	ld hl, .names
	ld c, "@"
.CheckName:
	dec b
	jr z, .Copy
.GetName:
	ld a, [hli]
	cp c
	jr z, .CheckName
	jr .GetName

.Copy:
	ld de, StringBuffer2
	ld bc, StringBuffer3 - StringBuffer2
	jp CopyBytes

.names
	db "Attack@"
	db "Defense@"
	db "Speed@"
	db "Spcl.Atk@"
	db "Spcl.Def@"
	db "Accuracy@"
	db "Evasion@"
	db "stats@" ; used by Curse
; 364e6


StatLevelMultipliers: ; 364e6
	db 25, 100 ; 0.25x
	db 28, 100 ; 0.28x
	db 33, 100 ; 0.33x
	db 40, 100 ; 0.40x
	db 50, 100 ; 0.50x
	db 66, 100 ; 0.66x
	db  1,   1 ; 1.00x
	db 15,  10 ; 1.50x
	db  2,   1 ; 2.00x
	db 25,  10 ; 2.50x
	db  3,   1 ; 3.00x
	db 35,  10 ; 3.50x
	db  4,   1 ; 4.00x
; 36500


BattleCommand_AllStatsUp: ; 36500
; allstatsup

; Attack
	call ResetMiss
	call BattleCommand_AttackUp
	call BattleCommand_StatUpMessage

; Defense
	call ResetMiss
	call BattleCommand_DefenseUp
	call BattleCommand_StatUpMessage

; Speed
	call ResetMiss
	call BattleCommand_SpeedUp
	call BattleCommand_StatUpMessage

; Special Attack
	call ResetMiss
	call BattleCommand_SpecialAttackUp
	call BattleCommand_StatUpMessage

; Special Defense
	call ResetMiss
	call BattleCommand_SpecialDefenseUp
	jp   BattleCommand_StatUpMessage
; 3652d


ResetMiss: ; 3652d
	xor a
	ld [AttackMissed], a
	ret

; 36532

LowerStat:: ; 36532
	ld a, b
	ld [LoweredStat], a

	ld hl, PlayerStatLevels
	ld a, [hBattleTurn]
	and a
	jr z, .got_target
	ld hl, EnemyStatLevels

.got_target
	ld a, [LoweredStat]
	and $f
	ld c, a
	ld b, 0
	add hl, bc
	ld b, [hl]
	dec b
	jr z, .cant_lower_anymore

	ld a, [LoweredStat]
	and $f0
	jr z, .got_num_stages
	dec b
	jr nz, .got_num_stages
	inc b

.got_num_stages
	ld [hl], b
	ld a, c
	cp 5
	jr nc, .accuracy_evasion

	push hl
	ld hl, BattleMonStats + 1
	ld de, PlayerStats
	ld a, [hBattleTurn]
	and a
	jr z, .got_target_2
	ld hl, EnemyMonStats + 1
	ld de, EnemyStats

.got_target_2
	call TryLowerStat
	pop hl
	jr z, .failed

.accuracy_evasion
	ld a, [hBattleTurn]
	and a
	jr z, .player

	call CalcEnemyStats

	jr .finish

.player
	call CalcPlayerStats

.finish
	xor a
	ld [FailedMessage], a
	ret

.failed
	inc [hl]

.cant_lower_anymore
	ld a, 2
	ld [FailedMessage], a
	ret

; 3658f


BattleCommand_TriStatusChance: ; 3658f
; tristatuschance

	call BattleCommand_EffectChance

; 1/3 chance of each status
.loop
	call BattleRandom
	swap a
	and %11
	jr z, .loop
; jump
	dec a
	ld hl, .ptrs
	rst JumpTable
	ret

.ptrs
	dw BattleCommand_ParalyzeTarget ; paralyze
	dw BattleCommand_FreezeTarget ; freeze
	dw BattleCommand_BurnTarget ; burn
; 365a7


BattleCommand_Curl: ; 365a7
; curl
	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	set SUBSTATUS_CURLED, [hl]
	ret

; 365af


BattleCommand_Burn:
; burn

	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVar
	bit BRN, a
	jp nz, .burned
	ld a, [TypeModifier]
	and a
	jp z, .didnt_affect
	call GetOpponentAbilityAfterMoldBreaker
	cp WATER_VEIL
	jp z, .ability_ok
	call IsLeafGuardActive
	jp z, .ability_ok
	call CheckIfTargetIsFireType
	jp z, .didnt_affect
	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_BURN
	jr nz, .no_item_protection
	ld a, [hl]
	ld [wNamedObjectIndexBuffer], a
	call GetItemName
	call AnimateFailedMove
	ld hl, ProtectedByText
	jp StdBattleTextBox

.no_item_protection
	ld a, [hBattleTurn]
	and a
	jr z, .dont_sample_failure

	ld a, [wLinkMode]
	and a
	jr nz, .dont_sample_failure

	ld a, [InBattleTowerBattle]
	and a
	jr nz, .dont_sample_failure

	ld a, [PlayerSubStatus2]
	bit SUBSTATUS_LOCK_ON, a
	jr nz, .dont_sample_failure

	call BattleRandom
	cp 1 + 25 percent
	jr c, .failed

.dont_sample_failure
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	and a
	jr nz, .failed
	ld a, [AttackMissed]
	and a
	jr nz, .failed
	call CheckSubstituteOpp
	jr nz, .failed
	ld c, 30
	call DelayFrames
	call AnimateCurrentMove
	ld a, $1
	ld [hBGMapMode], a
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	set BRN, [hl]
	call UpdateOpponentInParty
	call UpdateBattleHuds
	ld hl, WasBurnedText
	call StdBattleTextBox
	jp PostStatusWithSynchronize

.burned
	call AnimateFailedMove
	ld hl, AlreadyBurnedText
	jp StdBattleTextBox

.failed
	jp PrintDidntAffect2

.ability_ok
	farcall ShowEnemyAbilityActivation
.didnt_affect
	call AnimateFailedMove
	jp PrintDoesntAffect


BattleCommand_Hex:
; hex
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVar
	and a
	ret z
	jp DoubleDamage


BattleCommand_RaiseSubNoAnim: ; 365af
	ld hl, GetMonBackpic
	ld a, [hBattleTurn]
	and a
	jr z, .PlayerTurn
	ld hl, GetMonFrontpic
.PlayerTurn:
	xor a
	ld [hBGMapMode], a
	call CallBattleCore
	jp WaitBGMap

; 365c3


BattleCommand_LowerSubNoAnim: ; 365c3
	ld hl, DropPlayerSub
	ld a, [hBattleTurn]
	and a
	jr z, .PlayerTurn
	ld hl, DropEnemySub
.PlayerTurn:
	xor a
	ld [hBGMapMode], a
	call CallBattleCore
	jp WaitBGMap

; 365d7


CalcPlayerStats: ; 365d7
	ld hl, PlayerAtkLevel
	ld de, PlayerStats
	ld bc, BattleMonAttack
	jr CalcStats
CalcEnemyStats: ; 365fd
	ld hl, EnemyAtkLevel
	ld de, EnemyStats
	ld bc, EnemyMonAttack
CalcStats: ; 3661d
	ld a, 5
.loop
	push af
	ld a, [hli]
	push hl
	push bc

	ld c, a
	dec c
	ld b, 0
	ld hl, StatLevelMultipliers
	add hl, bc
	add hl, bc

	xor a
	ld [hMultiplicand + 0], a
	ld a, [de]
	ld [hMultiplicand + 1], a
	inc de
	ld a, [de]
	ld [hMultiplicand + 2], a
	inc de

	ld a, [hli]
	ld [hMultiplier], a
	call Multiply

	ld a, [hl]
	ld [hDivisor], a
	ld b, 4
	call Divide

	ld a, [hQuotient + 1]
	ld b, a
	ld a, [hQuotient + 2]
	or b
	jr nz, .check_maxed_out

	ld a, 1
	ld [hQuotient + 2], a
	jr .not_maxed_out

.check_maxed_out
	ld a, [hQuotient + 2]
	cp 999 % $100
	ld a, b
	sbc 999 / $100
	jr c, .not_maxed_out

	ld a, 999 % $100
	ld [hQuotient + 2], a
	ld a, 999 / $100
	ld [hQuotient + 1], a

.not_maxed_out
	pop bc
	ld a, [hQuotient + 1]
	ld [bc], a
	inc bc
	ld a, [hQuotient + 2]
	ld [bc], a
	inc bc
	pop hl
	pop af
	dec a
	jr nz, .loop

	ret

; 36671


BattleCommand_CheckRampage: ; 3671a
; checkrampage

	ld de, PlayerRolloutCount
	ld a, [hBattleTurn]
	and a
	jr z, .player
	ld de, EnemyRolloutCount
.player
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	bit SUBSTATUS_RAMPAGE, [hl]
	ret z
	ld a, [de]
	dec a
	ld [de], a
	jr nz, .continue_rampage

	res SUBSTATUS_RAMPAGE, [hl]
	call SwitchTurn
	call SafeCheckSafeguard
	push af
	call SwitchTurn
	pop af
	jr nz, .continue_rampage

	set SUBSTATUS_CONFUSED, [hl]
	call BattleRandom
	and %00000001
	inc a
	inc a
	inc de ; ConfuseCount
	ld [de], a
.continue_rampage
	ld b, rampage_command
	jp SkipToBattleCommand

; 36751


BattleCommand_Rampage: ; 36751
; rampage

; No rampage during Sleep Talk.
	ld a, BATTLE_VARS_STATUS
	call GetBattleVar
	and SLP
	ret nz

	ld de, PlayerRolloutCount
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld de, EnemyRolloutCount
.ok
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	set SUBSTATUS_RAMPAGE, [hl]
; Rampage for 1 or 2 more turns
	call BattleRandom
	and %00000001
	inc a
	ld [de], a
	ld a, 1
	ld [wSomeoneIsRampaging], a
	ret

; 36778


BattleCommand_Teleport: ; 36778
; teleport

	ld a, [BattleType]
	cp BATTLETYPE_SHINY
	jr z, .failed
	cp BATTLETYPE_TRAP ; or BATTLETYPE_LEGENDARY
	jr nc, .failed

; Can't teleport from a trainer battle
	ld a, [wBattleMode]
	dec a
	jr nz, .failed
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp RUN_AWAY
	jr z, .run_away
	ld a, BATTLE_VARS_SUBSTATUS2_OPP
	call GetBattleVar
	bit SUBSTATUS_CANT_RUN, a
	jr nz, .failed
	call CheckIfTrappedByAbility
	jr z, .failed
; Only need to check these next things if it's your turn
	ld a, [hBattleTurn]
	and a
	jr nz, .enemy_turn
; If your level is greater than the opponent's, you run without fail.
	ld a, [CurPartyLevel]
	ld b, a
	ld a, [BattleMonLevel]
	cp b
	jr nc, .run_away
	jr .got_vars
.enemy_turn
	ld a, [BattleMonLevel]
	ld b, a
	ld a, [CurPartyLevel]
	cp b
	jr nc, .run_away
.got_vars
; Generate a number between 0 and (YourLevel + TheirLevel).
	add b
	ld c, a
	inc c
.loop
	call BattleRandom
	cp c
	jr nc, .loop
; If that number is greater than 4 times your level, run away.
	srl b
	srl b
	cp b
	jr nc, .run_away

.failed
	call AnimateFailedMove
	jp PrintButItFailed

.run_away
	call UpdateBattleMonInParty
	xor a
	ld [wNumHits], a
	inc a
	ld [wForcedSwitch], a
	ld [wKickCounter], a
	call SetBattleDraw
	call BattleCommand_LowerSub
	call LoadMoveAnim
	ld c, 20
	call DelayFrames
	call SetBattleDraw

	ld hl, FledFromBattleText
	jp StdBattleTextBox

; 36804


CheckIfTrappedByAbility:
	call _CheckIfTrappedByAbility
	ld a, b
	and a
	ret

_CheckIfTrappedByAbility:
	; Wrapper around ability checks to ensure that no double-traps
	; happen.
	call CheckIfTrappedByAbilityInner
	ld a, b
	and a
	ret nz ; we aren't trapped
	call SwitchTurn
	call CheckIfTrappedByAbilityInner
	call SwitchTurn
	ld a, b
	and a
	jp z, .is_double_trap
	ld b, 0
	ret
.is_double_trap
	ld b, 1
	ret

CheckIfTrappedByAbilityInner:
	; Returns b=0 if trapped, b=1 otherwise
	ld b, 1
	; Ghost types are immune to all trapping abilities
	call CheckIfUserIsGhostType
	ret z
	ld a, BATTLE_VARS_ABILITY_OPP
	call GetBattleVar
	cp MAGNET_PULL
	jr z, .has_magnet_pull
	cp ARENA_TRAP
	jr z, .has_arena_trap
	cp SHADOW_TAG
	jr z, .is_trapped
	ret
.has_magnet_pull
	; Only works on Steel types
	call CheckIfUserIsSteelType
	ret nz
	jr .is_trapped
.has_arena_trap
	; Doesn't work on flying types or levitate users
	call CheckIfUserIsFlyingType
	ret z
	ld a, BATTLE_VARS_ABILITY
	cp LEVITATE
	ret z
.is_trapped
	ld b, 0
	ret

SetBattleDraw: ; 36804
	ld a, [wBattleResult]
	and $c0
	or $2
	ld [wBattleResult], a
	ret

; 3680f


BattleCommand_ForceSwitch: ; 3680f
; forceswitch

	ld a, [BattleType]
	cp BATTLETYPE_SHINY
	jp z, .fail
	cp BATTLETYPE_TRAP ; or BATTLETYPE_LEGENDARY
	jp nc, .fail
	call GetOpponentAbilityAfterMoldBreaker
	cp SUCTION_CUPS
	jp z, .fail
	ld a, [hBattleTurn]
	and a
	jp nz, .force_player_switch
	ld a, [AttackMissed]
	and a
	jr nz, .missed
	ld a, [wBattleMode]
	dec a
	jr nz, .trainer
	ld a, [CurPartyLevel]
	ld b, a
	ld a, [BattleMonLevel]
	cp b
	jr nc, .wild_force_flee
	add b
	ld c, a
	inc c
.random_loop_wild
	call BattleRandom
	cp c
	jr nc, .random_loop_wild
	srl b
	srl b
	cp b
	jr nc, .wild_force_flee
.missed
	jp .fail

.wild_force_flee
	call UpdateBattleMonInParty
	xor a
	ld [wNumHits], a
	inc a
	ld [wForcedSwitch], a
	call SetBattleDraw
	ld a, [wPlayerMoveStructAnimation]
	jp .succeed

.trainer
	call FindAliveEnemyMons
	jr c, .switch_fail
	ld a, [wEnemyGoesFirst]
	and a
	jr z, .switch_fail
	call UpdateEnemyMonInParty
	ld a, $1
	ld [wKickCounter], a
	call AnimateCurrentMove
	ld c, $14
	call DelayFrames
	hlcoord 1, 0
	lb bc, 4, 10
	call ClearBox
	ld c, 20
	call DelayFrames
	ld a, [OTPartyCount]
	ld b, a
	ld a, [CurOTMon]
	ld c, a
; select a random enemy mon to switch to
.random_loop_trainer
	call BattleRandom
	and $7
	cp b
	jr nc, .random_loop_trainer
	cp c
	jr z, .random_loop_trainer
	push af
	push bc
	ld hl, OTPartyMon1HP
	call GetPartyLocation
	ld a, [hli]
	or [hl]
	pop bc
	pop de
	jr z, .random_loop_trainer
	ld a, d
	inc a
	ld [wEnemySwitchMonIndex], a
	farcall ForceEnemySwitch

	ld hl, DraggedOutText
	call StdBattleTextBox

	ld hl, SpikesDamage_CheckMoldBreaker
	call CallBattleCore

	ld hl, RunActivationAbilities
	jp CallBattleCore

.switch_fail
	jp .fail

.force_player_switch
	ld a, [AttackMissed]
	and a
	jr nz, .player_miss

	ld a, [wBattleMode]
	dec a
	jr nz, .vs_trainer

	ld a, [BattleMonLevel]
	ld b, a
	ld a, [CurPartyLevel]
	cp b
	jr nc, .wild_succeed_playeristarget

	add b
	ld c, a
	inc c
.wild_random_loop_playeristarget
	call BattleRandom
	cp c
	jr nc, .wild_random_loop_playeristarget

	srl b
	srl b
	cp b
	jr nc, .wild_succeed_playeristarget

.player_miss
	jp .fail

.wild_succeed_playeristarget
	call UpdateBattleMonInParty
	xor a
	ld [wNumHits], a
	inc a
	ld [wForcedSwitch], a
	call SetBattleDraw
	ld a, [wEnemyMoveStructAnimation]
	jr .succeed

.vs_trainer
	call CheckPlayerHasMonToSwitchTo
	jr c, .fail

	ld a, [wEnemyGoesFirst]
	cp $1
	jr z, .switch_fail

	call UpdateBattleMonInParty
	ld a, $1
	ld [wKickCounter], a
	call AnimateCurrentMove
	ld c, 20
	call DelayFrames
	hlcoord 9, 7
	lb bc, 5, 11
	call ClearBox
	ld c, 20
	call DelayFrames
	ld a, [PartyCount]
	ld b, a
	ld a, [CurBattleMon]
	ld c, a
.random_loop_trainer_playeristarget
	call BattleRandom
	and $7
	cp b
	jr nc, .random_loop_trainer_playeristarget

	cp c
	jr z, .random_loop_trainer_playeristarget

	push af
	push bc
	ld hl, PartyMon1HP
	call GetPartyLocation
	ld a, [hli]
	or [hl]
	pop bc
	pop de
	jr z, .random_loop_trainer_playeristarget

	ld a, d
	ld [CurPartyMon], a
	ld hl, SwitchPlayerMon
	call CallBattleCore

	ld hl, DraggedOutText
	call StdBattleTextBox

	ld hl, SpikesDamage_CheckMoldBreaker
	call CallBattleCore

	ld hl, RunActivationAbilities
	jp CallBattleCore

.fail
	call BattleCommand_LowerSub
	call BattleCommand_MoveDelay
	call BattleCommand_RaiseSub
	jp PrintButItFailed

.succeed
	push af
	call SetBattleDraw
	ld a, $1
	ld [wKickCounter], a
	call AnimateCurrentMove
	ld c, 20
	call DelayFrames
	pop af
	ld hl, FledInFearText
	jp StdBattleTextBox

; 36994


CheckPlayerHasMonToSwitchTo: ; 36994
	ld a, [PartyCount]
	ld d, a
	ld e, 0
	ld bc, PARTYMON_STRUCT_LENGTH
.loop
	ld a, [CurBattleMon]
	cp e
	jr z, .next

	ld a, e
	ld hl, PartyMon1HP
	call AddNTimes
	ld a, [hli]
	or [hl]
	jr nz, .not_fainted

.next
	inc e
	dec d
	jr nz, .loop

	scf
	ret

.not_fainted
	and a
	ret

; 369b6


BattleCommand_EndLoop: ; 369b6
; endloop

; Loop back to the command before 'critical'.

	ld de, PlayerRolloutCount
	ld bc, PlayerDamageTaken
	ld a, [hBattleTurn]
	and a
	jr z, .got_addrs
	ld de, EnemyRolloutCount
	ld bc, EnemyDamageTaken
.got_addrs

	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	bit SUBSTATUS_IN_LOOP, [hl]
	jp nz, .in_loop
	set SUBSTATUS_IN_LOOP, [hl]
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVarAddr
	ld a, [hl]
	cp EFFECT_DOUBLE_HIT
	ld a, 1
	jr z, .double_hit
	ld a, [hl]
	cp EFFECT_TRIPLE_KICK
	jr nz, .not_triple_kick
.reject_triple_kick_sample
	call BattleRandom
	and $3
	jr z, .reject_triple_kick_sample
	dec a
	jr nz, .double_hit
	ld a, 1
	ld [bc], a
	jr .done_loop

.not_triple_kick
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp SKILL_LINK
	jr nz, .no_skill_link
	ld a, 3 ; ends up being 5 hits
	jr .got_number_hits
.no_skill_link
	call BattleRandom
	and $3
	cp 2
	jr c, .got_number_hits
	call BattleRandom
	and $3
.got_number_hits
	inc a
.double_hit
	ld [de], a
	inc a
	ld [bc], a
	jr .loop_back_to_critical

.in_loop
	ld a, [de]
	dec a
	ld [de], a
	jr nz, .loop_back_to_critical
.done_loop
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	res SUBSTATUS_IN_LOOP, [hl]

	ld hl, PlayerHitTimesText
	ld a, [hBattleTurn]
	and a
	jr z, .got_hit_n_times_text
	ld hl, EnemyHitTimesText
.got_hit_n_times_text
	xor a
	ld [bc], a
	ret

; Loop back to the command before 'critical'.
.loop_back_to_critical
	ld a, [BattleScriptBufferLoc + 1]
	ld h, a
	ld a, [BattleScriptBufferLoc]
	ld l, a
.not_critical
	ld a, [hld]
	cp critical_command
	jr nz, .not_critical
	inc hl
	ld a, h
	ld [BattleScriptBufferLoc + 1], a
	ld a, l
	ld [BattleScriptBufferLoc], a
	ret

; 36a82


BattleCommand_FlinchTarget: ; 36aa0
	call CheckSubstituteOpp
	ret nz

	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVar
	and 1 << FRZ | SLP
	ret nz

	call CheckOpponentWentFirst
	ret nz

	ld a, [EffectFailed]
	and a
	ret nz

	; fallthrough
; 36ab5


FlinchTarget: ; 36ab5
	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVarAddr
	set SUBSTATUS_FLINCHED, [hl]
	jp EndRechargeOpp

; 36abf


CheckOpponentWentFirst: ; 36abf
; Returns a=0, z if user went first
; Returns a=1, nz if opponent went first
	push bc
	ld a, [wEnemyGoesFirst] ; 0 if player went first
	ld b, a
	ld a, [hBattleTurn] ; 0 if it's the player's turn
	xor b ; 1 if opponent went first
	pop bc
	ret

; 36ac9


BattleCommand_KingsRock: ; 36ac9
	ld a, [AttackMissed]
	and a
	ret nz

	call CheckSubstituteOpp
	ret nz

	call GetUserItem
	ld a, b
	cp HELD_FLINCH_UP ; King's Rock/Razor Fang
	ret nz

	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVarAddr
	ld d, h
	ld e, l
	call GetUserItem
	call BattleRandom
	cp c
	jr z, .ok
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp STENCH
	ret nc
	call ShowAbilityActivation
.ok
	call EndRechargeOpp
	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVarAddr
	set SUBSTATUS_FLINCHED, [hl]
	ret

; 36af3


BattleCommand_CheckCharge: ; 36b3a
; checkcharge

	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	bit SUBSTATUS_CHARGED, [hl]
	ret z
	res SUBSTATUS_CHARGED, [hl]
	res SUBSTATUS_UNDERGROUND, [hl]
	res SUBSTATUS_FLYING, [hl]
	ld b, charge_command
	jp SkipToBattleCommand

; 36b4d


BattleCommand_Charge: ; 36b4d
; charge

	call BattleCommand_ClearText
	ld a, BATTLE_VARS_STATUS
	call GetBattleVar
	and SLP
	jr z, .awake

	call BattleCommand_MoveDelay
	call BattleCommand_RaiseSub
	call PrintButItFailed
	jp EndMoveEffect

.awake
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	set SUBSTATUS_CHARGED, [hl]

	ld hl, IgnoredOrders2Text
	ld a, [AlreadyDisobeyed]
	and a
	call nz, StdBattleTextBox

	call BattleCommand_LowerSub
	xor a
	ld [wNumHits], a
	inc a
	ld [wKickCounter], a
	call LoadMoveAnim
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	cp FLY
	jr z, .flying
	cp DIG
	jr z, .flying
	call BattleCommand_RaiseSub
	jr .not_flying

.flying
	call DisappearUser
.not_flying
	ld a, BATTLE_VARS_SUBSTATUS3
	call GetBattleVarAddr
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld b, a
	cp FLY
	jr z, .set_flying
	cp DIG
	jr nz, .dont_set_digging
	set SUBSTATUS_UNDERGROUND, [hl]
	jr .dont_set_digging

.set_flying
	set SUBSTATUS_FLYING, [hl]

.dont_set_digging
	call CheckUserIsCharging
	jr nz, .mimic
	ld a, BATTLE_VARS_LAST_COUNTER_MOVE
	call GetBattleVarAddr
	ld [hl], b
	ld a, BATTLE_VARS_LAST_MOVE
	call GetBattleVarAddr
	ld [hl], b

.mimic
	call ResetDamage

	ld hl, .UsedText
	call BattleTextBox

	ld a, [hBattleTurn]
	and a
	ld hl, BattleMonItem
	jr z, .got_item
	ld hl, EnemyMonItem
.got_item
	ld a, [hl]
	cp POWER_HERB
	jp nz, EndMoveEffect
	farcall ConsumeUsersItem
	ld hl, .PowerHerb
	jp BattleTextBox

.UsedText:
	text_jump UnknownText_0x1c0d0e ; "[USER]"
	start_asm
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar

	cp SOLAR_BEAM
	ld hl, .SolarBeam
	jr z, .done

	cp SKY_ATTACK
	ld hl, .SkyAttack
	jr z, .done

	cp FLY
	ld hl, .Fly
	jr z, .done

	cp DIG
	ld hl, .Dig

.done
	ret

.SolarBeam:
; 'took in sunlight!'
	text_jump UnknownText_0x1c0d26
	db "@"

.SkyAttack:
; 'is glowing!'
	text_jump UnknownText_0x1c0d4e
	db "@"

.Fly:
; 'flew up high!'
	text_jump UnknownText_0x1c0d5c
	db "@"

.Dig:
; 'dug a hole!'
	text_jump UnknownText_0x1c0d6c
	db "@"
; 36c2c

.PowerHerb:
	text_jump Text_PowerHerbActivated
	db "@"

BattleCommand_TrapTarget: ; 36c2d
; traptarget

	ld a, [AttackMissed]
	and a
	ret nz
	ld hl, wEnemyWrapCount
	ld de, wEnemyTrappingMove
	ld a, [hBattleTurn]
	and a
	jr z, .got_trap
	ld hl, wPlayerWrapCount
	ld de, wPlayerTrappingMove

.got_trap
	ld a, [hl]
	and a
	ret nz
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp INFILTRATOR
	jr z, .bypass_sub
	ld a, BATTLE_VARS_SUBSTATUS4_OPP
	call GetBattleVar
	bit SUBSTATUS_SUBSTITUTE, a
	ret nz
.bypass_sub
	push bc
	call GetUserItem
	ld a, b
	cp HELD_PROLONG_WRAP
	pop bc
	jr z, .seven_turns
	call BattleRandom
	and 1
	add 4
	jr .got_count
.seven_turns
	ld a, 7
.got_count
	ld [hl], a
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld [de], a
	ld b, a
	ld hl, .Traps

.find_trap_text
	ld a, [hli]
	cp b
	jr z, .found_trap_text
	inc hl
	inc hl
	jr .find_trap_text

.found_trap_text
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp StdBattleTextBox

.Traps:
	dbw WRAP,      WrappedByText     ; 'was WRAPPED by'
	dbw FIRE_SPIN, FireSpinTrapText  ; 'was trapped!'
	dbw WHIRLPOOL, WhirlpoolTrapText ; 'was trapped!'
; 36c7e


BattleCommand_Mist: ; 36c7e
; mist

	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	bit SUBSTATUS_MIST, [hl]
	jr nz, .already_mist
	set SUBSTATUS_MIST, [hl]
	call AnimateCurrentMove
	ld hl, MistText
	jp StdBattleTextBox

.already_mist
	call AnimateFailedMove
	jp PrintButItFailed

; 36c98


BattleCommand_FocusEnergy: ; 36c98
; focusenergy

	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	bit SUBSTATUS_FOCUS_ENERGY, [hl]
	jr nz, .already_pumped
	set SUBSTATUS_FOCUS_ENERGY, [hl]
	call AnimateCurrentMove
	ld hl, GettingPumpedText
	jp StdBattleTextBox

.already_pumped
	call AnimateFailedMove
	jp PrintButItFailed

; 36cb2


BattleCommand_Recoil: ; 36cb2
; recoil

	ld hl, BattleMonMaxHP
	ld a, [hBattleTurn]
	and a
	ld a, [LastPlayerMove]
	jr z, .got_hp
	ld hl, EnemyMonMaxHP
	ld a, [LastEnemyMove]
.got_hp
	ld b, a
	cp STRUGGLE
	jp z, .StruggleRecoil

	; For all other moves, potentially disable
	; recoil based on ability
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp ROCK_HEAD
	ret z
	cp MAGIC_GUARD
	ret z

	ld a, b
	cp DOUBLE_EDGE
	jr z, .OneThirdRecoil
	cp FLARE_BLITZ
	jr z, .OneThirdRecoil
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld d, a
; get 1/4 damage or 1 HP, whichever is higher
	ld a, [CurDamage]
	ld b, a
	ld a, [CurDamage + 1]
	ld c, a
	srl b
	rr c
	srl b
	rr c
.recoil_floor
	ld a, b
	or c
	jr nz, .min_damage
	inc c
.min_damage
	ld a, [hli]
	ld [Buffer2], a
	ld a, [hl]
	ld [Buffer1], a
	dec hl
	dec hl
	ld a, [hl]
	ld [Buffer3], a
	sub c
	ld [hld], a
	ld [Buffer5], a
	ld a, [hl]
	ld [Buffer4], a
	sbc b
	ld [hl], a
	ld [Buffer6], a
	jr nc, .dont_ko
	xor a
	ld [hli], a
	ld [hl], a
	ld hl, Buffer5
	ld [hli], a
	ld [hl], a
.dont_ko
	hlcoord 11, 9
	ld a, [hBattleTurn]
	and a
	ld a, 1
	jr z, .animate_hp_bar
	hlcoord 1, 2
	xor a
.animate_hp_bar
	ld [wWhichHPBar], a
	predef AnimateHPBar
	call RefreshBattleHuds
.recoil_text
	ld hl, RecoilText
	jp StdBattleTextBox

.StruggleRecoil
	ld hl, GetQuarterMaxHP
	call CallBattleCore
	ld hl, SubtractHPFromUser
	call CallBattleCore
	call UpdateUserInParty
	jp .recoil_text

.OneThirdRecoil
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld d, a
	ld a, [CurDamage]
	ld [hDividend], a
	ld a, [CurDamage + 1]
	ld [hDividend + 1], a
	ld a, 3
	ld [hDivisor], a
	ld b, 2
	call Divide
	ld a, [hQuotient + 2]
	ld c, a
	ld a, [hQuotient + 1]
	ld b, a
	jr .recoil_floor

; 36d1d


BattleCommand_ConfuseTarget: ; 36d1d
; confusetarget

	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_CONFUSE
	ret z
	call GetOpponentAbilityAfterMoldBreaker
	cp OWN_TEMPO
	jr nz, .no_own_tempo
	farcall ShowEnemyAbilityActivation
	ret
.no_own_tempo
	ld a, [EffectFailed]
	and a
	ret nz
	call SafeCheckSafeguard
	ret nz
	call CheckSubstituteOpp
	ret nz
	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVarAddr
	bit SUBSTATUS_CONFUSED, [hl]
	ret nz
	jr BattleCommand_FinishConfusingTarget


BattleCommand_Confuse: ; 36d3b
; confuse

	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_CONFUSE
	jr nz, .no_item_protection
	ld a, [hl]
	ld [wNamedObjectIndexBuffer], a
	call GetItemName
	call AnimateFailedMove
	ld hl, ProtectedByText
	jp StdBattleTextBox

.no_item_protection
	call GetOpponentAbilityAfterMoldBreaker
	cp OWN_TEMPO
	jr nz, .no_ability_protection
	farcall ShowEnemyAbilityActivation
	ld hl, DoesntAffectText
	jp StdBattleTextBox

.no_ability_protection
	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVarAddr
	bit SUBSTATUS_CONFUSED, [hl]
	jr z, .not_already_confused
	call AnimateFailedMove
	ld hl, AlreadyConfusedText
	jp StdBattleTextBox

.not_already_confused
	call CheckSubstituteOpp
	jr nz, BattleCommand_Confuse_CheckSnore_Swagger_ConfuseHit
	ld a, [AttackMissed]
	and a
	jr nz, BattleCommand_Confuse_CheckSnore_Swagger_ConfuseHit
BattleCommand_FinishConfusingTarget: ; 36d70
	ld bc, EnemyConfuseCount
	ld a, [hBattleTurn]
	and a
	jr z, .got_confuse_count
	ld bc, PlayerConfuseCount

.got_confuse_count
	set SUBSTATUS_CONFUSED, [hl]
	call BattleRandom
	and %11
	inc a
	inc a
	ld [bc], a

	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_CONFUSE_HIT
	jr z, .got_effect
	cp EFFECT_SNORE
	jr z, .got_effect
	cp EFFECT_SWAGGER
	jr z, .got_effect
	call AnimateCurrentMove

.got_effect
	ld de, ANIM_CONFUSED
	call PlayOpponentBattleAnim

	ld hl, BecameConfusedText
	call StdBattleTextBox

	farcall UseEnemyConfusionHealingItem
	farcall RunEnemyStatusHealAbilities
	ret

; 36db6

BattleCommand_Confuse_CheckSnore_Swagger_ConfuseHit: ; 36db6
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_CONFUSE_HIT
	ret z
	cp EFFECT_SNORE
	ret z
	cp EFFECT_SWAGGER
	ret z
	jp PrintDidntAffect2

; 36dc7


BattleCommand_Paralyze: ; 36dc7
; paralyze

	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVar
	bit PAR, a
	jr nz, .paralyzed
	ld a, [TypeModifier]
	and a
	jp z, .didnt_affect
	call GetOpponentAbilityAfterMoldBreaker
	cp LIMBER
	jr z, .ability_ok
	call IsLeafGuardActive
	jr z, .ability_ok
	call CheckIfTargetIsElectricType
	jr z, .didnt_affect
	call GetOpponentItem
	ld a, b
	cp HELD_PREVENT_PARALYZE
	jr nz, .no_item_protection
	ld a, [hl]
	ld [wNamedObjectIndexBuffer], a
	call GetItemName
	call AnimateFailedMove
	ld hl, ProtectedByText
	jp StdBattleTextBox

.no_item_protection
	ld a, [hBattleTurn]
	and a
	jr z, .dont_sample_failure

	ld a, [wLinkMode]
	and a
	jr nz, .dont_sample_failure

	ld a, [InBattleTowerBattle]
	and a
	jr nz, .dont_sample_failure

	ld a, [PlayerSubStatus2]
	bit SUBSTATUS_LOCK_ON, a
	jr nz, .dont_sample_failure

	call BattleRandom
	cp 1 + 25 percent
	jr c, .failed
	jr .dont_sample_failure

.paralyzed
	call AnimateFailedMove
	ld hl, AlreadyParalyzedText
	jp StdBattleTextBox

.failed
	jp PrintDidntAffect2

.ability_ok
	farcall ShowEnemyAbilityActivation
.didnt_affect
	call AnimateFailedMove
	jp PrintDoesntAffect

.dont_sample_failure
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	and a
	jr nz, .failed
	ld a, [AttackMissed]
	and a
	jr nz, .failed
	call CheckSubstituteOpp
	jr nz, .failed
	ld c, 30
	call DelayFrames
	call AnimateCurrentMove
	ld a, $1
	ld [hBGMapMode], a
	ld a, BATTLE_VARS_STATUS_OPP
	call GetBattleVarAddr
	set PAR, [hl]
	call UpdateOpponentInParty
	call UpdateBattleHuds
	call PrintParalyze
	jp PostStatusWithSynchronize

; 36e5b


BattleCommand_Substitute: ; 36e7c
; substitute
	call BattleCommand_MoveDelay

	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVar
	bit SUBSTATUS_SUBSTITUTE, a
	jr nz, .already_has_sub
	farcall GetQuarterMaxHP
	push bc
	call CompareHP
	pop bc
	jr c, .too_weak_to_sub
	jr z, .too_weak_to_sub

	ld hl, PlayerSubstituteHP
	ld a, [hBattleTurn]
	and a
	jr z, .got_hp
	ld hl, EnemySubstituteHP
.got_hp
	ld a, b
	ld [hli], a
	ld [hl], c
	farcall SubtractHPFromUser
	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	set SUBSTATUS_SUBSTITUTE, [hl]

	ld hl, wPlayerWrapCount
	ld de, wPlayerTrappingMove
	ld a, [hBattleTurn]
	and a
	jr z, .player
	ld hl, wEnemyWrapCount
	ld de, wEnemyTrappingMove
.player
	xor a
	ld [hl], a
	ld [de], a
	call _CheckBattleEffects
	jr c, .no_anim

	xor a
	ld [wNumHits], a
	ld [FXAnimIDHi], a
	ld [wKickCounter], a
	ld a, SUBSTITUTE
	call LoadAnim
	jr .finish

.no_anim
	call BattleCommand_RaiseSubNoAnim
.finish
	ld hl, MadeSubstituteText
	call StdBattleTextBox
	jp RefreshBattleHuds

.already_has_sub
	call CheckUserIsCharging
	call nz, BattleCommand_RaiseSub
	ld hl, HasSubstituteText
	jr .jp_stdbattletextbox

.too_weak_to_sub
	call CheckUserIsCharging
	call nz, BattleCommand_RaiseSub
	ld hl, TooWeakSubText
.jp_stdbattletextbox
	jp StdBattleTextBox

; 36f0b

BattleCommand_RechargeNextTurn: ; 36f0b
; rechargenextturn
	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	set SUBSTATUS_RECHARGE, [hl]
	ret

; 36f13


EndRechargeOpp: ; 36f13
	push hl
	ld a, BATTLE_VARS_SUBSTATUS4_OPP
	call GetBattleVarAddr
	res SUBSTATUS_RECHARGE, [hl]
	pop hl
	ret

; 36f1d


BattleCommand_Rage: ; 36f1d
; rage
	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	set SUBSTATUS_RAGE, [hl]
	ret

; 36f25


BattleCommand_DoubleFlyingDamage: ; 36f25
; doubleflyingdamage
	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVar
	bit SUBSTATUS_FLYING, a
	ret z
	jr DoubleDamage

; 36f2f


BattleCommand_DoubleUndergroundDamage: ; 36f2f
; doubleundergrounddamage
	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVar
	bit SUBSTATUS_UNDERGROUND, a
	ret z

	; fallthrough
; 36f37


DoubleDamage: ; 36f37
	ld hl, CurDamage + 1
	sla [hl]
	dec hl
	rl [hl]
	jr nc, .quit

	ld a, $ff
	ld [hli], a
	ld [hl], a
.quit
	ret

; 36f46


BattleCommand_LeechSeed: ; 36f9d
; leechseed
	ld a, [AttackMissed]
	and a
	jr nz, .evaded
	call CheckSubstituteOpp
	jr nz, .evaded
	call CheckIfTargetIsGrassType
	jr z, .grass

	ld a, BATTLE_VARS_SUBSTATUS4_OPP
	call GetBattleVarAddr
	bit SUBSTATUS_LEECH_SEED, [hl]
	jr nz, .evaded
	set SUBSTATUS_LEECH_SEED, [hl]
	call AnimateCurrentMove
	ld hl, WasSeededText
	jp StdBattleTextBox

.grass
	call AnimateFailedMove
	jp PrintDoesntAffect

.evaded
	call AnimateFailedMove
	ld hl, EvadedText
	jp StdBattleTextBox

; 36fe1


BattleCommand_Splash: ; 36fe1
	call AnimateCurrentMove
	jp PrintNothingHappened

; 36fed


BattleCommand_Disable: ; 36fed
; disable

	ld a, [AttackMissed]
	and a
	jr nz, .failed

	ld de, EnemyDisableCount
	ld hl, EnemyMonMoves
	ld a, [hBattleTurn]
	and a
	jr z, .got_moves
	ld de, PlayerDisableCount
	ld hl, BattleMonMoves
.got_moves

	ld a, [de]
	and a
	jr nz, .failed

	ld a, BATTLE_VARS_LAST_COUNTER_MOVE_OPP
	call GetBattleVar
	and a
	jr z, .failed
	cp STRUGGLE
	jr z, .failed

	ld b, a
	ld c, $ff
.loop
	inc c
	ld a, [hli]
	cp b
	jr nz, .loop

	ld a, [hBattleTurn]
	and a
	ld hl, EnemyMonPP
	jr z, .got_pp
	ld hl, BattleMonPP
.got_pp
	ld b, 0
	add hl, bc
	ld a, [hl]
	and a
	jr z, .failed
	call ShowPotentialAbilityActivation
	; check for AnimationsDisabled to determine if this is via Cursed Body, in
	; which we want to change the duration to always be 3 turns
	ld a, [AnimationsDisabled]
	and a
	ld a, 4
	jr z, .got_duration
	ld a, 2
.got_duration
	inc c
	swap c
	add c
	ld [de], a
	call AnimateCurrentMove
	ld hl, DisabledMove
	ld a, [hBattleTurn]
	and a
	jr nz, .got_disabled_move_pointer
	inc hl
.got_disabled_move_pointer
	ld a, BATTLE_VARS_LAST_COUNTER_MOVE_OPP
	call GetBattleVar
	ld [hl], a
	ld [wNamedObjectIndexBuffer], a
	call GetMoveName
	ld hl, WasDisabledText
	jp StdBattleTextBox

.failed
	jp FailDisable

; 3705c


BattleCommand_PayDay: ; 3705c
; payday

	call CheckSubstituteOpp
	ret nz

	xor a
	ld hl, StringBuffer1
	ld [hli], a

	ld a, [hBattleTurn]
	and a
	ld a, [BattleMonLevel]
	jr z, .ok
	ld a, [EnemyMonLevel]
.ok

	push bc
	ld b, a
	add a
	add a
	add b
	pop bc

	ld hl, wPayDayMoney + 2
	add [hl]
	ld [hld], a
	jr nc, .done
	inc [hl]
	dec hl
	jr nz, .done
	inc [hl]
.done
	ld hl, CoinsScatteredText
	jp StdBattleTextBox

; 3707f


BattleCommand_Conversion: ; 3707f
; conversion

	ld hl, BattleMonMoves
	ld de, BattleMonType1
	ld a, [hBattleTurn]
	and a
	jr z, .got_moves
	ld hl, EnemyMonMoves
	ld de, EnemyMonType1
.got_moves
	push de
	ld c, 0
	ld de, StringBuffer1
.loop
	push hl
	ld b, 0
	add hl, bc
	ld a, [hl]
	pop hl
	and a
	jr z, .okay
	push hl
	push bc
	dec a
	ld hl, Moves + MOVE_TYPE
	call GetMoveAttr
	ld [de], a
	inc de
	pop bc
	pop hl
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .loop
.okay
	ld a, $ff
	ld [de], a
	inc de
	ld [de], a
	inc de
	ld [de], a
	pop de
	ld hl, StringBuffer1
.loop2
	ld a, [hl]
	cp -1
	jr z, .fail
	cp UNKNOWN_T
	jr z, .next
	ld a, [de]
	cp [hl]
	jr z, .next
	inc de
	ld a, [de]
	dec de
	cp [hl]
	jr nz, .done
.next
	inc hl
	jr .loop2

.fail
	call AnimateFailedMove
	jp PrintButItFailed

.done
.loop3
	call BattleRandom
	and %11 ; NUM_MOVES - 1
	ld c, a
	ld b, 0
	ld hl, StringBuffer1
	add hl, bc
	ld a, [hl]
	cp -1
	jr z, .loop3
	cp UNKNOWN_T
	jr z, .loop3
	ld a, [de]
	cp [hl]
	jr z, .loop3
	inc de
	ld a, [de]
	dec de
	cp [hl]
	jr z, .loop3
	ld a, [hl]
	ld [de], a
	inc de
	ld [de], a
	ld [wNamedObjectIndexBuffer], a
	farcall GetTypeName
	call AnimateCurrentMove
	ld hl, TransformedTypeText
	jp StdBattleTextBox

; 3710e


BattleCommand_ResetStats: ; 3710e
; resetstats

	ld a, BASE_STAT_LEVEL
	ld hl, PlayerStatLevels
	call .Fill
	ld hl, EnemyStatLevels
	call .Fill

	ld a, [hBattleTurn]
	push af

	call SetPlayerTurn
	call CalcPlayerStats
	call SetEnemyTurn
	call CalcEnemyStats

	pop af
	ld [hBattleTurn], a

	call AnimateCurrentMove

	ld hl, EliminatedStatsText
	jp StdBattleTextBox

; same structure as ResetPlayerStatLevels and ResetEnemyStatLevels
.Fill:
	ld b, NUM_LEVEL_STATS
.loop
	ld [hli], a
	dec b
	jr nz, .loop
	ret

; 3713e


BattleCommand_Heal: ; 3713e
; heal

	farcall CheckFullHP_b
	ld a, b
	and a
	jr z, .hp_full
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	cp REST
	jr nz, .not_rest

	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp INSOMNIA
	jr z, .ability_prevents_rest
	cp VITAL_SPIRIT
	jr z, .ability_prevents_rest
	call SwitchTurn
	call IsLeafGuardActive
	push af
	call SwitchTurn
	pop af
	jr z, .ability_prevents_rest
	call BattleCommand_MoveDelay
	ld a, BATTLE_VARS_SUBSTATUS2
	call GetBattleVarAddr
	res SUBSTATUS_TOXIC, [hl]
	ld a, BATTLE_VARS_STATUS
	call GetBattleVarAddr
	ld a, [hl]
	and a
	ld [hl], REST_TURNS + 1
	ld hl, WentToSleepText
	jr z, .no_status_to_heal
	ld hl, RestedText
.no_status_to_heal
	call StdBattleTextBox
	farcall GetMaxHP
	jr .finish
.not_rest
	farcall GetHalfMaxHP
.finish
	call AnimateCurrentMove
	farcall RestoreHP
	call UpdateUserInParty
	call RefreshBattleHuds
	ld hl, RegainedHealthText
	jp StdBattleTextBox

.ability_prevents_rest
	call AnimateFailedMove
	farcall ShowAbilityActivation
	ret

.hp_full
	call AnimateFailedMove
	ld hl, HPIsFullText
	jp StdBattleTextBox

; 371cd

INCLUDE "battle/effects/transform.asm"

BattleSideCopy: ; 372c6
; Copy bc bytes from hl to de if it's the player's turn.
; Copy bc bytes from de to hl if it's the enemy's turn.
	ld a, [hBattleTurn]
	and a
	jr z, .copy

; Swap hl and de
	push hl
	ld h, d
	ld l, e
	pop de
.copy
	jp CopyBytes

; 372d2


BattleEffect_ButItFailed: ; 372d2
	call AnimateFailedMove
	jp PrintButItFailed

; 372d8


ClearLastMove: ; 372d8
	ld a, BATTLE_VARS_LAST_COUNTER_MOVE
	call GetBattleVarAddr
	xor a
	ld [hl], a

	ld a, BATTLE_VARS_LAST_MOVE
	call GetBattleVarAddr
	xor a
	ld [hl], a
	ret

; 372e7


ResetActorDisable: ; 372e7
	ld a, [hBattleTurn]
	and a
	jr z, .player

	xor a
	ld [EnemyDisableCount], a
	ld [EnemyDisabledMove], a
	ret

.player
	xor a
	ld [PlayerDisableCount], a
	ld [DisabledMove], a
	ret

; 372fc


BattleCommand_Screen: ; 372fc
; screen

	ld hl, PlayerScreens
	ld bc, PlayerLightScreenCount
	ld a, [hBattleTurn]
	and a
	jr z, .got_screens_pointer
	ld hl, EnemyScreens
	ld bc, EnemyLightScreenCount

.got_screens_pointer
	ld a, BATTLE_VARS_MOVE_EFFECT
	call GetBattleVar
	cp EFFECT_LIGHT_SCREEN
	jr nz, .reflect

	bit SCREENS_LIGHT_SCREEN, [hl]
	jr nz, .failed
	set SCREENS_LIGHT_SCREEN, [hl]
	ld hl, LightScreenEffectText
	jr .set_timer
.reflect
	bit SCREENS_REFLECT, [hl]
	jr nz, .failed
	set SCREENS_REFLECT, [hl]
	inc bc ; LightScreenCount -> ReflectCount
	ld hl, ReflectEffectText
.set_timer
	ld a, HELD_PROLONG_SCREENS
	call GetItemBoostedDuration
	ld [bc], a
	call AnimateCurrentMove
	jp StdBattleTextBox

.failed
	call AnimateFailedMove
	jp PrintButItFailed

; 3733d


GetItemBoostedDuration:
	push bc
	push hl
	ld c, a
	push bc
	call GetUserItem
	ld a, b
	pop bc
	cp c
	cp b
	ld a, 5
	jr nz, .got_duration
	ld a, 8
.got_duration
	pop hl
	pop bc
	ret


PrintDoesntAffect: ; 3733d
; 'it doesn't affect'
	ld hl, DoesntAffectText
	jp StdBattleTextBox

; 37343


PrintNothingHappened: ; 37343
; 'but nothing happened!'
	ld hl, NothingHappenedText
	jp StdBattleTextBox

; 37349


TryPrintButItFailed: ; 37349
	ld a, [AlreadyFailed]
	and a
	ret nz

	; fallthrough
; 3734e


PrintButItFailed: ; 3734e
; 'but it failed!'
	ld hl, ButItFailedText
	jp StdBattleTextBox

; 37354


FailSnore:
FailDisable:
FailConversion2:
FailAttract:
FailForesight:
FailSpikes:
	call AnimateFailedMove
	; fallthrough
; 37357

PrintDidntAffect: ; 37360
; 'it didn't affect'
	ld hl, DidntAffect1Text
	jp StdBattleTextBox

; 37366


PrintDidntAffect2: ; 37366
	call AnimateFailedMove
	ld hl, DidntAffect1Text ; 'it didn't affect'
	ld de, DidntAffect2Text ; 'it didn't affect'
	jp FailText_CheckOpponentProtect

; 37372


PrintParalyze: ; 37372
; 'paralyzed! maybe it can't attack!'
	ld hl, ParalyzedText
	jp StdBattleTextBox

; 37378

CheckSubstituteOpp_b:
; stores result in b rather than zero flag (ld a, b; and a for equavilent result),
; used for farcalls
	call CheckSubstituteOpp
	ld b, 0
	ret z
	ld b, 1
	ret

CheckSubstituteOpp: ; 37378
; returns z when not behind a sub (or if overridden by Infiltrator or sound)
	ld a, BATTLE_VARS_ABILITY
	call GetBattleVar
	cp INFILTRATOR
	ret z
	push bc
	push de
	push hl
	ld a, BATTLE_VARS_MOVE
	call GetBattleVar
	ld hl, SoundMoves
	ld de, 1
	call IsInArray
	pop hl
	pop de
	pop bc
	jr nc, .no_sound_move
	xor a
	ret
.no_sound_move
	ld a, BATTLE_VARS_SUBSTATUS4_OPP
	call GetBattleVar
	bit SUBSTATUS_SUBSTITUTE, a
	ret

; 37380


BattleCommand_SelfDestruct: ; 37380
	call GetOpponentAbilityAfterMoldBreaker
	cp DAMP
	ret z ; nullification ability checks handle messages
	ld a, BATTLEANIM_PLAYER_DAMAGE
	ld [wNumHits], a
	ld c, 3
	call DelayFrames
	ld a, BATTLE_VARS_STATUS
	call GetBattleVarAddr
	xor a
	ld [hli], a
	inc hl
	ld [hli], a
	ld [hl], a
	ld a, $1
	ld [wKickCounter], a
	call BattleCommand_LowerSub
	call LoadMoveAnim
	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	res SUBSTATUS_LEECH_SEED, [hl]
	ld a, BATTLE_VARS_SUBSTATUS2_OPP
	call GetBattleVarAddr
	res SUBSTATUS_DESTINY_BOND, [hl]
	call _CheckBattleEffects
	ret nc
	farcall DrawPlayerHUD
	farcall DrawEnemyHUD
	call WaitBGMap
	jp RefreshBattleHuds

; 373c9


INCLUDE "battle/effects/metronome.asm"


CheckUserMove: ; 37462
; Return z if the user has move a.
	ld b, a
	ld de, BattleMonMoves
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld de, EnemyMonMoves
.ok

	ld c, NUM_MOVES
.loop
	ld a, [de]
	inc de
	cp b
	ret z

	dec c
	jr nz, .loop

	ld a, 1
	and a
	ret

; 3747b


ResetTurn: ; 3747b
	ld hl, wPlayerCharging
	ld a, [hBattleTurn]
	and a
	jr z, .player
	ld hl, wEnemyCharging

.player
	ld [hl], 1
	xor a
	ld [AlreadyDisobeyed], a
	call DoMove
	jp EndMoveEffect

; 37492


INCLUDE "battle/effects/thief.asm"


BattleCommand_ArenaTrap: ; 37517
; arenatrap

; Doesn't work on an absent opponent.

	call CheckHiddenOpponent
	jr nz, .failed

; Don't trap if the opponent is already trapped.

	ld a, BATTLE_VARS_SUBSTATUS2
	call GetBattleVarAddr
	bit SUBSTATUS_CANT_RUN, [hl]
	jr nz, .failed

; Otherwise trap the opponent.

	set SUBSTATUS_CANT_RUN, [hl]
	call AnimateCurrentMove
	ld hl, CantEscapeNowText
	jp StdBattleTextBox

.failed
	call AnimateFailedMove
	jp PrintButItFailed

; 37536


BattleCommand_Defrost: ; 37563
; defrost

; Thaw the user.

	ld a, BATTLE_VARS_STATUS
	call GetBattleVarAddr
	bit FRZ, [hl]
	ret z
	res FRZ, [hl]

; Don't update the enemy's party struct in a wild battle.

	ld a, [hBattleTurn]
	and a
	jr z, .party

	ld a, [wBattleMode]
	dec a
	jr z, .done

.party
	ld a, MON_STATUS
	call UserPartyAttr
	res FRZ, [hl]

.done
	call RefreshBattleHuds
	ld hl, WasDefrostedText
	jp StdBattleTextBox

; 37588


INCLUDE "battle/effects/curse.asm"

INCLUDE "battle/effects/protect.asm"

INCLUDE "battle/effects/endure.asm"

INCLUDE "battle/effects/spikes.asm"

INCLUDE "battle/effects/foresight.asm"

INCLUDE "battle/effects/perish_song.asm"

INCLUDE "battle/effects/rollout.asm"


BattleCommand_FuryCutter: ; 37792
; furycutter

	ld hl, PlayerFuryCutterCount
	ld a, [hBattleTurn]
	and a
	jr z, .go
	ld hl, EnemyFuryCutterCount

.go
	ld a, [AttackMissed]
	and a
	jp nz, ResetFuryCutterCount

	inc [hl]

; Damage capped at 3 turns' worth (40 x 2 x 2 = 160).
	ld a, [hl]
	ld b, a
	cp 3
	jr c, .checkdouble
	ld b, 2

.checkdouble
	dec b
	ret z

; Double the damage
	ld hl, CurDamage + 1
	sla [hl]
	dec hl
	rl [hl]
	jr nc, .checkdouble

; No overflow
	ld a, $ff
	ld [hli], a
	ld [hl], a
	ret

; 377be


ResetFuryCutterCount: ; 377be

	push hl

	ld hl, PlayerFuryCutterCount
	ld a, [hBattleTurn]
	and a
	jr z, .reset
	ld hl, EnemyFuryCutterCount

.reset
	xor a
	ld [hl], a

	pop hl
	ret

; 377ce


INCLUDE "battle/effects/attract.asm"

BattleCommand_HappinessPower: ; 3784b
; happinesspower
	push bc
	ld hl, BattleMonHappiness
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld hl, EnemyMonHappiness
.ok
	xor a
	ld [hMultiplicand + 0], a
	ld [hMultiplicand + 1], a
	ld a, [hl]
	ld [hMultiplicand + 2], a
	ld a, 10
	ld [hMultiplier], a
	call Multiply
	ld a, 25
	ld [hDivisor], a
	ld b, 4
	call Divide
	ld a, [hQuotient + 2]
	ld d, a
	pop bc
	ret

; 37874


BattleCommand_Safeguard: ; 37939
; safeguard

	ld hl, PlayerScreens
	ld de, PlayerSafeguardCount
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld hl, EnemyScreens
	ld de, EnemySafeguardCount
.ok
	bit SCREENS_SAFEGUARD, [hl]
	jr nz, .failed
	set SCREENS_SAFEGUARD, [hl]
	ld a, 5
	ld [de], a
	call AnimateCurrentMove
	ld hl, CoveredByVeilText
	jp StdBattleTextBox

.failed
	call AnimateFailedMove
	jp PrintButItFailed

; 37962


SafeCheckSafeguard: ; 37962
	push hl
	ld hl, EnemyScreens
	ld a, [EnemyAbility]
	ld b, a
	ld a, [hBattleTurn]
	and a
	jr z, .got_turn
	ld hl, PlayerScreens
	ld a, [PlayerAbility]
	ld b, a

.got_turn
	bit SCREENS_SAFEGUARD, [hl]
	jr z, .done
	ld a, b
	cp INFILTRATOR

.done
	pop hl
	ret

; 37972


BattleCommand_CheckSafeguard: ; 37972
; checksafeguard
	ld hl, EnemyScreens
	ld a, [EnemyAbility]
	ld b, a
	ld a, [hBattleTurn]
	and a
	jr z, .got_turn
	ld hl, PlayerScreens
	ld a, [PlayerAbility]
	ld b, a
.got_turn
	bit SCREENS_SAFEGUARD, [hl]
	ret z
	ld a, b
	cp INFILTRATOR
	ret z
	ld a, 1
	ld [AttackMissed], a
	call BattleCommand_MoveDelay
	ld hl, SafeguardProtectText
	call StdBattleTextBox
	jp EndMoveEffect

; 37991


BattleCommand_GetMagnitude: ; 37991
; getmagnitude

	push bc
	call BattleRandom
	ld b, a
	ld hl, .Magnitudes
.loop
	ld a, [hli]
	cp b
	jr nc, .ok
	inc hl
	inc hl
	jr .loop

.ok
	ld d, [hl]
	push de
	inc hl
	ld a, [hl]
	ld [wTypeMatchup], a
	call BattleCommand_MoveDelay
	ld hl, MagnitudeText
	call StdBattleTextBox
	pop de
	pop bc
	ret

.Magnitudes:
	;  /255, BP, magnitude
	db  13,  10,  4
	db  38,  30,  5
	db  89,  50,  6
	db 166,  70,  7
	db 217,  90,  8
	db 242, 110,  9
	db 255, 150, 10
; 379c9


BattleCommand_BatonPass: ; 379c9
; batonpass

	ld a, [hBattleTurn]
	and a
	jp nz, .Enemy


; Need something to switch to
	call CheckAnyOtherAlivePartyMons
	jp z, FailedBatonPass

	call UpdateBattleMonInParty
	call AnimateCurrentMove

	ld c, 50
	call DelayFrames

; Transition into switchmon menu
	call LoadStandardMenuDataHeader
	farcall SetUpBattlePartyMenu_NoLoop

	farcall ForcePickSwitchMonInBattle

; Return to battle scene
	call ClearPalettes
	farcall _LoadBattleFontsHPBar
	call CloseWindow
	call ClearSprites
	hlcoord 1, 0
	lb bc, 4, 10
	call ClearBox
	ld b, SCGB_BATTLE_COLORS
	call GetSGBLayout
	call SetPalettes
	call BatonPass_LinkPlayerSwitch

	ld hl, PassedBattleMonEntrance
	call CallBattleCore

	call ResetBatonPassStatus
	ret


.Enemy:

; Wildmons don't have anything to switch to
	ld a, [wBattleMode]
	dec a ; WILDMON
	jp z, FailedBatonPass

	call CheckAnyOtherAliveEnemyMons
	jp z, FailedBatonPass

	call UpdateEnemyMonInParty
	call AnimateCurrentMove
	call BatonPass_LinkEnemySwitch

; Passed enemy PartyMon entrance
	xor a
	ld [wEnemySwitchMonIndex], a
	ld hl, EnemySwitch_SetMode
	call CallBattleCore
	ld hl, ResetBattleParticipants
	call CallBattleCore
	ld a, 1
	ld [wTypeMatchup], a
	ld hl, ApplyStatLevelMultiplierOnAllStats
	call CallBattleCore

	ld hl, SpikesDamage
	call CallBattleCore

	ld hl, RunActivationAbilities
	call CallBattleCore

	jr ResetBatonPassStatus

; 37a67


BatonPass_LinkPlayerSwitch: ; 37a67
	ld a, [wLinkMode]
	and a
	ret z

	ld a, 1
	ld [wPlayerAction], a

	call LoadStandardMenuDataHeader
	ld hl, LinkBattleSendReceiveAction
	call CallBattleCore
	call CloseWindow

	xor a
	ld [wPlayerAction], a
	ret

; 37a82


BatonPass_LinkEnemySwitch: ; 37a82
	ld a, [wLinkMode]
	and a
	ret z

	call LoadStandardMenuDataHeader
	ld hl, LinkBattleSendReceiveAction
	call CallBattleCore

	ld a, [OTPartyCount]
	add BATTLEACTION_SWITCH1
	ld b, a
	ld a, [wBattleAction]
	cp BATTLEACTION_SWITCH1
	jr c, .baton_pass
	cp b
	jr c, .switch

.baton_pass
	ld a, [CurOTMon]
	add BATTLEACTION_SWITCH1
	ld [wBattleAction], a
.switch
	jp CloseWindow

; 37aab


FailedBatonPass: ; 37aab
	call AnimateFailedMove
	jp PrintButItFailed

; 37ab1


ResetBatonPassStatus: ; 37ab1
; Reset status changes that aren't passed by Baton Pass.

	; Disable isn't passed.
	call ResetActorDisable

	; Attraction isn't passed.
	ld hl, PlayerSubStatus1
	res SUBSTATUS_IN_LOVE, [hl]
	ld hl, EnemySubStatus1
	res SUBSTATUS_IN_LOVE, [hl]
	ld hl, PlayerSubStatus2

	ld a, BATTLE_VARS_SUBSTATUS2
	call GetBattleVarAddr
	res SUBSTATUS_TRANSFORMED, [hl]
	res SUBSTATUS_ENCORED, [hl]

	; New mon hasn't used a move yet.
	ld a, BATTLE_VARS_LAST_MOVE
	call GetBattleVarAddr
	ld [hl], 0

	xor a
	ld [wPlayerWrapCount], a
	ld [wEnemyWrapCount], a
	ret

; 37ae9


CheckAnyOtherAlivePartyMons: ; 37ae9
	ld hl, PartyMon1HP
	ld a, [PartyCount]
	ld d, a
	ld a, [CurBattleMon]
	ld e, a
	jr CheckAnyOtherAliveMons

; 37af6


CheckAnyOtherAliveEnemyMons: ; 37af6
	ld hl, OTPartyMon1HP
	ld a, [OTPartyCount]
	ld d, a
	ld a, [CurOTMon]
	ld e, a

	; fallthrough
; 37b01

CheckAnyOtherAliveMons: ; 37b01
; Check for nonzero HP starting from partymon
; HP at hl for d partymons, besides current mon e.

; Return nz if any are alive.

	xor a
	ld b, a
	ld c, a
.loop
	ld a, c
	cp d
	jr z, .done
	cp e
	jr z, .next

	ld a, [hli]
	or b
	ld b, a
	ld a, [hld]
	or b
	ld b, a

.next
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc
	pop bc
	inc c
	jr .loop

.done
	ld a, b
	and a
	ret

; 37b1d


BattleCommand_Pursuit: ; 37b1d
; pursuit
; Double damage if the opponent is switching.

	ld hl, wEnemyIsSwitching
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld hl, wPlayerIsSwitching
.ok
	ld a, [hl]
	and a
	ret z

	ld hl, CurDamage + 1
	sla [hl]
	dec hl
	rl [hl]
	ret nc

	ld a, $ff
	ld [hli], a
	ld [hl], a
	ret

; 37b39


BattleCommand_ClearHazards: ; 37b39
; clearhazards

	ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	bit SUBSTATUS_LEECH_SEED, [hl]
	jr z, .not_leeched
	res SUBSTATUS_LEECH_SEED, [hl]
	ld hl, ShedLeechSeedText
	call StdBattleTextBox
.not_leeched

	ld hl, PlayerScreens
	ld de, wPlayerWrapCount
	ld a, [hBattleTurn]
	and a
	jr z, .got_screens_wrap
	ld hl, EnemyScreens
	ld de, wEnemyWrapCount
.got_screens_wrap
	bit SCREENS_SPIKES, [hl]
	jr z, .no_spikes
	res SCREENS_SPIKES, [hl]
	ld hl, BlewSpikesText
	push de
	call StdBattleTextBox
	pop de
.no_spikes

	ld a, [de]
	and a
	ret z
	xor a
	ld [de], a
	ld hl, ReleasedByText
	jp StdBattleTextBox

; 37b74


BattleCommand_HealMornOrDay:
	ld d, 0
	jr BattleCommand_HealTime
BattleCommand_HealNite:
	ld d, 1
BattleCommand_HealTime:
; d contains default state: 1 = lesser heal. Reverses during night
; Don't factor in time of day in link battles.
	ld a, [wLinkMode]
	and a
	ld a, 0 ; not xor a; preserve carry flag
	jr nz, .timecheck_ok
	ld a, [TimeOfDay]
	cp NITE
	ld a, d
	jr nz, .timecheck_ok
	; on nighttime, default state is reversed
	xor 1
.timecheck_ok
	add 2
	ld d, a
	; d=1: heal 100%, d=2: heal 50%, d=3: heal 25%, d=4: heal 12.5%

	farcall CheckFullHP_b
	ld a, b
	and a
	jr z, .full

	call GetWeatherAfterCloudNine
	and a
	jr z, .heal

; Heal amount doubles in sun, halves in any other active weather
	dec d
	cp WEATHER_SUN
	jr z, .heal
	inc d
	inc d

.heal
	call AnimateCurrentMove

	farcall GetMaxHP
.loop
	dec d
	jr z, .done
	srl b
	rr c
	jr .loop
.done
	; minimum healing cap is 1
	ld a, c
	or b
	jr nz, .amount_ok
	inc c
.amount_ok
	farcall RestoreHP
	call UpdateUserInParty

; 'regained health!'
	ld hl, RegainedHealthText
	jp StdBattleTextBox

.full
	call AnimateFailedMove
	ld hl, HPIsFullText
	jp StdBattleTextBox

BattleCommand_HiddenPower: ; 37be8
; hiddenpower

	ld a, [AttackMissed]
	and a
	ret nz
	farcall HiddenPowerDamage
	ret

; 37bf4


BattleCommand_StartSun:
	ld b, WEATHER_SUN
	ld c, HELD_PROLONG_SUN
	ld hl, SunGotBrightText
	jr BattleCommand_StartWeather
BattleCommand_StartRain:
	ld b, WEATHER_RAIN
	ld c, HELD_PROLONG_RAIN
	ld hl, DownpourText
	jr BattleCommand_StartWeather
BattleCommand_StartSandstorm:
	ld b, WEATHER_SANDSTORM
	ld c, HELD_PROLONG_SANDSTORM
	ld hl, SandstormBrewedText
	jr BattleCommand_StartWeather
BattleCommand_StartHail:
	ld b, WEATHER_HAIL
	ld c, HELD_PROLONG_HAIL
	ld hl, HailStartedText
BattleCommand_StartWeather:
	ld a, [Weather]
	cp b
	jr z, .failed

	ld a, b
	ld [Weather], a
	ld a, c
	call GetItemBoostedDuration
	ld [WeatherCount], a
	call AnimateCurrentMove
	jp StdBattleTextBox ; hl has text pointer already

.failed
	call AnimateFailedMove
	jp PrintButItFailed


BattleCommand_BellyDrum: ; 37c1a
; bellydrum
	farcall GetHalfMaxHP
	call CompareHP
	jr c, .failed
	jr z, .failed

	call BattleCommand_AttackUp2
	ld a, [AttackMissed]
	and a
	jr nz, .failed

	push bc
	call AnimateCurrentMove
	pop bc
	farcall GetHalfMaxHP
	farcall SubtractHPFromUser
	call UpdateUserInParty
	ld a, 5

.max_attack_loop
	push af
	call BattleCommand_AttackUp2
	pop af
	dec a
	jr nz, .max_attack_loop

	ld hl, BellyDrumText
	jp StdBattleTextBox

.failed
	call AnimateFailedMove
	jp PrintButItFailed

; 37c55


BattleCommand_DoubleMinimizeDamage: ; 37ce6
; doubleminimizedamage

	ld hl, wEnemyMinimized
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld hl, wPlayerMinimized
.ok
	ld a, [hl]
	and a
	ret z
	ld hl, CurDamage + 1
	sla [hl]
	dec hl
	rl [hl]
	ret nc
	ld a, $ff
	ld [hli], a
	ld [hl], a
	ret

; 37d02


BattleCommand_SkipSunCharge: ; 37d02
; mimicsuncharge
	call GetWeatherAfterCloudNine
	cp WEATHER_SUN
	ret nz
	ld b, charge_command
	jp SkipToBattleCommand

; 37d0d


BattleCommand_CheckFutureSight: ; 37d0d
; checkfuturesight

	ld hl, wPlayerFutureSightCount
	ld de, wPlayerFutureSightDamage
	ld a, [hBattleTurn]
	and a
	jr z, .ok
	ld hl, wEnemyFutureSightCount
	ld de, wEnemyFutureSightDamage
.ok

	ld a, [hl]
	and a
	ret z
	cp 1
	ret nz

	ld [hl], 0
	ld a, [de]
	inc de
	ld [CurDamage], a
	ld a, [de]
	ld [CurDamage + 1], a
	ld b, futuresight_command
	jp SkipToBattleCommand

; 37d34

BattleCommand_FutureSight: ; 37d34
; futuresight

	call CheckUserIsCharging
	jr nz, .AlreadyChargingFutureSight
	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	ld b, a
	ld a, BATTLE_VARS_LAST_COUNTER_MOVE
	call GetBattleVarAddr
	ld [hl], b
	ld a, BATTLE_VARS_LAST_MOVE
	call GetBattleVarAddr
	ld [hl], b
.AlreadyChargingFutureSight:
	ld hl, wPlayerFutureSightCount
	ld a, [hBattleTurn]
	and a
	jr z, .GotFutureSightCount
	ld hl, wEnemyFutureSightCount
.GotFutureSightCount:
	ld a, [hl]
	and a
	jr nz, .failed
	ld a, 4
	ld [hl], a
	call BattleCommand_LowerSub
	call BattleCommand_MoveDelay
	ld hl, ForesawAttackText
	call StdBattleTextBox
	call BattleCommand_RaiseSub
	ld de, wPlayerFutureSightDamage
	ld a, [hBattleTurn]
	and a
	jr z, .StoreDamage
	ld de, wEnemyFutureSightDamage
.StoreDamage:
	ld hl, CurDamage
	ld a, [hl]
	ld [de], a
	ld [hl], 0
	inc hl
	inc de
	ld a, [hl]
	ld [de], a
	ld [hl], 0
	jp EndMoveEffect

.failed
	pop bc
	call ResetDamage
	call AnimateFailedMove
	call PrintButItFailed
	jp EndMoveEffect

; 37d94


BattleCommand_ThunderAccuracy: ; 37d94
; thunderaccuracy

	ld a, BATTLE_VARS_MOVE_TYPE
	call GetBattleVarAddr
	inc hl
	call GetWeatherAfterCloudNine
	cp WEATHER_RAIN
	jr z, .rain
	cp WEATHER_SUN
	ret nz
	ld [hl], 50 percent + 1
	ret

.rain
	ld [hl], 100 percent
	ret

; 37daa


CheckHiddenOpponent: ; 37daa
	ld a, BATTLE_VARS_SUBSTATUS3_OPP
	call GetBattleVar
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	ret

; 37db2


GetUserItem: ; 37db2
; Return the effect of the user's item in bc, and its id at hl.
	ld hl, BattleMonItem
	ld a, [hBattleTurn]
	and a
	jr z, .go
	ld hl, EnemyMonItem
.go
	ld b, [hl]
	jp GetItemHeldEffect

; 37dc1


GetOpponentItem: ; 37dc1
; Return the effect of the opponent's item in bc, and its id at hl.
	call SwitchTurn
	call GetUserItem
	jp SwitchTurn

GetUserItemAfterUnnerve:
; Returns the effect of the user's item in bc, and its id at hl,
; unless it's a Berry and Unnerve is in effect.
	call GetUserItem
	ld a, BATTLE_VARS_ABILITY_OPP
	call GetBattleVar
	cp UNNERVE
	ret nz
	ld a, [hl]
	push de
	push hl
	ld de, 1
	ld hl, UnnerveItemsBlocked
	call IsInArray
	pop hl
	pop de
	ret nc
	ld hl, NoItem
	ld b, HELD_NONE
	ret

UnnerveItemsBlocked:
	db ORAN_BERRY
	db SITRUS_BERRY
	db PECHA_BERRY
	db RAWST_BERRY
	db CHERI_BERRY
	db CHESTO_BERRY
	db ASPEAR_BERRY
	db PERSIM_BERRY
	db LUM_BERRY
	db LEPPA_BERRY
	db -1
NoItem:
	db NO_ITEM


GetItemHeldEffect: ; 37dd0
; Return the effect of item b in bc.
	ld a, b
	and a
	ret z

	push hl
	ld hl, ItemAttributes + 2
	dec a
	ld c, a
	ld b, 0
	ld a, Item2Attributes - Item1Attributes
	call AddNTimes
	ld a, BANK(ItemAttributes)
	call GetFarHalfword
	ld b, l
	ld c, h
	pop hl
	ret

; 37de9


AnimateCurrentMoveEitherSide: ; 37de9
	push hl
	push de
	push bc
	ld a, [wKickCounter]
	push af
	call BattleCommand_LowerSub
	pop af
	ld [wKickCounter], a
	call PlayDamageAnim
	call BattleCommand_RaiseSub
	pop bc
	pop de
	pop hl
	ret

; 37e01


AnimateCurrentMove: ; 37e01
	ld a, [AnimationsDisabled]
	and a
	ret nz
	push hl
	push de
	push bc
	ld a, [wKickCounter]
	push af
	call BattleCommand_LowerSub
	pop af
	ld [wKickCounter], a
	call LoadMoveAnim
	call BattleCommand_RaiseSub
	pop bc
	pop de
	pop hl
	ret

; 37e19


PlayDamageAnim: ; 37e19
	xor a
	ld [FXAnimIDHi], a

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	and a
	ret z

	ld [FXAnimIDLo], a

	ld a, [hBattleTurn]
	and a
	ld a, BATTLEANIM_ENEMY_DAMAGE
	jr z, .player
	ld a, BATTLEANIM_PLAYER_DAMAGE

.player
	ld [wNumHits], a

	jp PlayUserBattleAnim

; 37e36


LoadMoveAnim: ; 37e36
	xor a
	ld [wNumHits], a
	ld [FXAnimIDHi], a

	ld a, BATTLE_VARS_MOVE_ANIM
	call GetBattleVar
	and a
	ret z

	; fallthrough
; 37e44


LoadAnim: ; 37e44

	ld [FXAnimIDLo], a

	; fallthrough
; 37e47


PlayUserBattleAnim: ; 37e47
	push hl
	push de
	push bc
	farcall PlayBattleAnim
	pop bc
	pop de
	pop hl
	ret

; 37e54


PlayOpponentBattleAnim: ; 37e54
	ld a, e
	ld [FXAnimIDLo], a
	ld a, d
	ld [FXAnimIDHi], a
	xor a
	ld [wNumHits], a

	push hl
	push de
	push bc
	call SwitchTurn

	farcall PlayBattleAnim

	call SwitchTurn
	pop bc
	pop de
	pop hl
	ret

; 37e73


CallBattleCore: ; 37e73
	ld a, BANK(BattleCore)
	rst FarCall
	ret

; 37e77

ShowPotentialAbilityActivation:
; This avoids duplicating checks to avoid text spam. This will run
; ShowAbilityActivation if animations are disabled (something only abilities do)
	ld a, [AnimationsDisabled]
	and a
	ret z
	; push/pop hl isn't redundant, farcall clobbers it
	push hl
	farcall ShowAbilityActivation
	pop hl
	ret

AnimateFailedMove: ; 37e77
	ld a, [AnimationsDisabled]
	and a
	ret nz
	call BattleCommand_LowerSub
	call BattleCommand_MoveDelay
	jp BattleCommand_RaiseSub

; 37e80


BattleCommand_MoveDelay: ; 37e80
; movedelay
; Wait 40 frames.
	ld c, 40
	jp DelayFrames

; 37e85


BattleCommand_ClearText: ; 37e85
; cleartext

; Used in multi-hit moves.
	ld hl, .text
	jp BattleTextBox

.text
	db "@"
; 37e8c


SkipToBattleCommand: ; 37e8c
; Skip over commands until reaching command b.
	ld a, [BattleScriptBufferLoc + 1]
	ld h, a
	ld a, [BattleScriptBufferLoc]
	ld l, a
.loop
	ld a, [hli]
	cp b
	jr nz, .loop

	ld a, h
	ld [BattleScriptBufferLoc + 1], a
	ld a, l
	ld [BattleScriptBufferLoc], a
	ret

; 37ea1


GetMoveAttr: ; 37ea1
; Assuming hl = Moves + x, return attribute x of move a.
	push bc
	ld bc, MOVE_LENGTH
	call AddNTimes
	call GetMoveByte
	pop bc
	ret

; 37ead


GetMoveData: ; 37ead
; Copy move struct a to de.
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld a, Bank(Moves)
	jp FarCopyBytes

; 37ebb


GetMoveByte: ; 37ebb
	ld a, BANK(Moves)
	jp GetFarByte

; 37ec0


DisappearUser: ; 37ec0
	farcall _DisappearUser
	ret

; 37ec7


AppearUserLowerSub: ; 37ec7
	farcall _AppearUserLowerSub
	ret

; 37ece


AppearUserRaiseSub: ; 37ece
	farcall _AppearUserRaiseSub
	ret

; 37ed5


_CheckBattleEffects: ; 37ed5
; Checks the options.  Returns carry if battle animations are disabled.
	push hl
	push de
	push bc
	farcall CheckBattleEffects
	pop bc
	pop de
	pop hl
	ret
