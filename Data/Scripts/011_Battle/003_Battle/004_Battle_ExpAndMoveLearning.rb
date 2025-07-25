class PokeBattle_Battle
  #=============================================================================
  # Gaining Experience
  #=============================================================================
  def pbGainExp
    # Play wild victory music if it's the end of the battle (has to be here)
    @scene.pbWildBattleSuccess if wildBattle? && pbAllFainted?(1) && !pbAllFainted?(0)
    return if !@internalBattle || !@expGain
    # Go through each battler in turn to find the Pokémon that participated in
    # battle against it, and award those Pokémon Exp/EVs
    expAll = (GameData::Item.exists?(:EXPALL) && $PokemonBag.pbHasItem?(:EXPALL))
    p1 = pbParty(0)
    @battlers.each do |b|
      next unless b && b.opposes?   # Can only gain Exp from fainted foes
      next if b.participants.length==0
      next unless b.fainted? || b.captured
      # Count the number of participants
      numPartic = 0
      b.participants.each do |partic|
        next unless p1[partic] && p1[partic].able? && pbIsOwner?(0,partic)
        numPartic += 1
      end
      # Find which Pokémon have an Exp Share
      expShare = []
      if !expAll
        eachInTeam(0,0) do |pkmn,i|
          next if !pkmn.able?
          next if !pkmn.hasItem?(:EXPSHARE) && GameData::Item.try_get(@initialItems[0][i]) != :EXPSHARE
          expShare.push(i)
        end
      end
      # Calculate EV and Exp gains for the participants
      if numPartic>0 || expShare.length>0 || expAll
        # Gain EVs and Exp for participants
        eachInTeam(0,0) do |pkmn,i|
          next if !pkmn.able?
          next unless b.participants.include?(i) || expShare.include?(i)
          pbGainEVsOne(i,b)
          pbGainExpOne(i,b,numPartic,expShare,expAll)
        end
        # Gain EVs and Exp for all other Pokémon because of Exp All
        if expAll
          showMessage = true
          eachInTeam(0,0) do |pkmn,i|
            next if !pkmn.able?
            next if b.participants.include?(i) || expShare.include?(i)
            pbDisplayPaused(_INTL("¡El resto de tu equipo también ha ganado experiencia!")) if showMessage
            showMessage = false
            pbGainEVsOne(i,b)
            pbGainExpOne(i,b,numPartic,expShare,expAll,false)
          end
        end
      end
      # Clear the participants array
      b.participants = []
    end
  end

  def pbGainEVsOne(idxParty,defeatedBattler)
    pkmn = pbParty(0)[idxParty]   # The Pokémon gaining EVs from defeatedBattler
    evYield = defeatedBattler.pokemon.evYield
    # Num of effort points pkmn already has
    evTotal = 0
    GameData::Stat.each_main { |s| evTotal += pkmn.ev[s.id] }
    # Modify EV yield based on pkmn's held item
    if !BattleHandlers.triggerEVGainModifierItem(pkmn.item,pkmn,evYield)
      BattleHandlers.triggerEVGainModifierItem(@initialItems[0][idxParty],pkmn,evYield)
    end
    # Double EV gain because of Pokérus
    if pkmn.pokerusStage>=1   # Infected or cured
      evYield.each_key { |stat| evYield[stat] *= 2 }
    end
    # Gain EVs for each stat in turn
    if pkmn.shadowPokemon? && pkmn.saved_ev
      pkmn.saved_ev.each_value { |e| evTotal += e }
      GameData::Stat.each_main do |s|
        evGain = evYield[s.id].clamp(0, Pokemon::EV_STAT_LIMIT - pkmn.ev[s.id] - pkmn.saved_ev[s.id])
        evGain = evGain.clamp(0, Pokemon::EV_LIMIT - evTotal)
        pkmn.saved_ev[s.id] += evGain
        evTotal += evGain
      end
    else
      GameData::Stat.each_main do |s|
        evGain = evYield[s.id].clamp(0, Pokemon::EV_STAT_LIMIT - pkmn.ev[s.id])
        evGain = evGain.clamp(0, Pokemon::EV_LIMIT - evTotal)
        pkmn.ev[s.id] += evGain
        evTotal += evGain
      end
    end
  end

  def pbGainExpOne(idxParty,defeatedBattler,numPartic,expShare,expAll,showMessages=true)
    pkmn = pbParty(0)[idxParty]   # The Pokémon gaining EVs from defeatedBattler
    growth_rate = pkmn.growth_rate
    # Don't bother calculating if gainer is already at max Exp
    if pkmn.exp>=growth_rate.maximum_exp
      pkmn.calc_stats   # To ensure new EVs still have an effect
      return
    end
    isPartic    = defeatedBattler.participants.include?(idxParty)
    hasExpShare = expShare.include?(idxParty)
    level = defeatedBattler.level
    # Main Exp calculation
    exp = 0
    a = level*defeatedBattler.pokemon.base_exp
    if expShare.length>0 && (isPartic || hasExpShare)
      if numPartic==0   # No participants, all Exp goes to Exp Share holders
        exp = a / (Settings::SPLIT_EXP_BETWEEN_GAINERS ? expShare.length : 1)
      elsif Settings::SPLIT_EXP_BETWEEN_GAINERS   # Gain from participating and/or Exp Share
        exp = a/(2*numPartic) if isPartic
        exp += a/(2*expShare.length) if hasExpShare
      else   # Gain from participating and/or Exp Share (Exp not split)
        exp = (isPartic) ? a : a/2
      end
    elsif isPartic   # Participated in battle, no Exp Shares held by anyone
      exp = a / (Settings::SPLIT_EXP_BETWEEN_GAINERS ? numPartic : 1)
    elsif expAll   # Didn't participate in battle, gaining Exp due to Exp All
      # NOTE: Exp All works like the Exp Share from Gen 6+, not like the Exp All
      #       from Gen 1, i.e. Exp isn't split between all Pokémon gaining it.
      exp = a/2
    end
    return if exp<=0
    # Pokémon gain more Exp from trainer battles
    
    #############################################
    # Si pasas la mitad del juego, after Shadow

    if ($game_switches[650])
      exp = (exp*0.8).floor if trainerBattle?
    else
      exp = (exp * 1.1).floor if trainerBattle?
    end

    if ($game_switches[894])
      exp = (exp*0.75).floor if trainerBattle?
    end
    #############################################

    # Scale the gained Exp based on the gainer's level (or not)
    if Settings::SCALED_EXP_FORMULA
      exp /= 5
      levelAdjust = (2*level+10.0)/(pkmn.level+level+10.0)
      levelAdjust = levelAdjust**5
      levelAdjust = Math.sqrt(levelAdjust)
      exp *= levelAdjust
      exp = exp.floor
      exp += 1 if isPartic || hasExpShare
    else
      exp /= 7
    end
    # Foreign Pokémon gain more Exp
    isOutsider = (pkmn.owner.id != pbPlayer.id ||
                 (pkmn.owner.language != 0 && pkmn.owner.language != pbPlayer.language))
#######################################################
# Sistema de LevelCap Simple by Clara. Credits not needed but are appreciated.
#######################################################
#==================CONFIGURACIÓN=======================
levelCapExp = 1 #Experiencia que el pokémon ganará full perrón uwu
levelCapExp = 69 if $game_switches[136] #Experiencia que el pokémon ganará full perrón uwu


levelCap=13
levelCap=18 if $game_switches[136] #Darek
levelCap=24 if $game_switches[4] #1ra medalla
levelCap=26 if $game_switches[275] #Comandante
levelCap=29 if $game_switches[288] #2nda medalla
levelCap=32 if $game_switches[317] #Pelea Darek
levelCap=35 if $game_switches[348] #Salen del jardín
levelCap=37 if $game_switches[411] #Fin líder gym
levelCap=38 if $game_switches[450] #Entras al barco
levelCap=42 if $game_switches[452] #Sales del barco
levelCap=44 if $game_switches[495] #Fin arco Sakura
levelCap=45 if $game_switches[522] #Latios a salvo
levelCap=47 if $game_switches[530] #Vuelves a ser PN
levelCap=50 if $game_switches[546] #Fin evento Bosque
levelCap=43 if $game_switches[578] #Arco Eda start
levelCap=47 if $game_switches[585] #Safe fuente
levelCap=50 if $game_switches[615] #Hasta la batalla de Hakan
levelCap=51 if $game_switches[660] #Empieza arco Shadow - Final Arco Shadow
levelCap=53 if $game_switches[768] #Hasta el final de la cueva Magnética
levelCap=55 if $game_switches[806] #Desde Ruta 17 hasta evento Galería de Arte 
levelCap=70 if $game_switches[873] #Desde el paso floral hasta terminar el pasado 
levelCap=57 if $game_switches[887] #Desde que empiezas a buscar a Rodolfo
levelCap=59 if $game_switches[894] #Momento cloacas
levelCap=63 if $game_switches[957] #Cuando empieza teatro y palacio hasta su final, para Eda, Sakura y PN
levelCap=70 if $game_switches[1099] #Solo momento en el que vas con Edward
levelCap=65 if $game_switches[1113] #Cuando vas con PN
levelCap=67 if $game_switches[1146] #Combate contra Liberty
levelCap=68 if $game_switches[1216] #Desde Ruta 20 - Hasta Dynamó
levelCap=70 if $game_switches[1212] #Después de Dynamó - Hasta Terminar Arco Isla del Sur
levelCap=72 if $game_switches[1300] #Terminar Arco Isla del Sur - Empieza Arco del Pasado

$game_variables[99] = levelCap

#levelCap=35 if $Trainer.numbadges==3 #3 medalla
#levelCap=45 if $Trainer.numbadges==4 #4 medalla
#levelCap=50 if $game_variables[8]==1 #5 medalla
#levelCap=55 if $game_switches[9] #6 medalla
#levelCap=60 if $game_switches[10] #7 medalla
#levelCap=75 if $game_switches[11] #8 medalla
#======================================================
if defined?(pkmn) #Compatibilidad con la v18 y v19
thispoke = pkmn
end

exp=levelCapExp if (thispoke.level >= levelCap) && exp>levelCapExp
#####################################################
    #if isOutsider
      #if pkmn.owner.language != 0 && pkmn.owner.language != pbPlayer.language
        #exp = (exp*1.5).floor
      #else
        #exp = (exp*1.3).floor
      #end
    #end
    # Modify Exp gain based on EXP Charm's Presence
    exp = (exp * 1.5).floor if GameData::Item.exists?(:EXPCHARM) && $PokemonBag.pbHasItem?(:EXPCHARM)
    # Modify Exp gain based on pkmn's held item
    i = BattleHandlers.triggerExpGainModifierItem(pkmn.item,pkmn,exp)
    if i<0
      i = BattleHandlers.triggerExpGainModifierItem(@initialItems[0][idxParty],pkmn,exp)
    end
    exp = i if i>=0
    # Boost Exp gained with high affection
    if Settings::AFFECTION_EFFECTS && @internalBattle && pkmn.affection_level >= 4 && !pkmn.mega?
      exp = exp * 6 / 5
      isOutsider = true   # To show the "boosted Exp" message
    end
    # Make sure Exp doesn't exceed the maximum
    expFinal = growth_rate.add_exp(pkmn.exp, exp)
    expGained = expFinal-pkmn.exp
    return if expGained<=0
    # "Exp gained" message
    if showMessages
      if isOutsider
        pbDisplayPaused(_INTL("{1} ganó {2} puntos de Exp!",pkmn.name,expGained))
      else
        pbDisplayPaused(_INTL("{1} ganó {2} Exp. Points!",pkmn.name,expGained))
      end
    end
    curLevel = pkmn.level
    newLevel = growth_rate.level_from_exp(expFinal)
    if newLevel<curLevel
      debugInfo = "Levels: #{curLevel}->#{newLevel} | Exp: #{pkmn.exp}->#{expFinal} | gain: #{expGained}"
      raise RuntimeError.new(
         _INTL("{1}'s new level is less than its\r\ncurrent level, which shouldn't happen.\r\n[Debug: {2}]",
         pkmn.name,debugInfo))
    end
    # Give Exp
    if pkmn.shadowPokemon?
      pkmn.exp += expGained
      return
    end
    tempExp1 = pkmn.exp
    battler = pbFindBattler(idxParty)
    loop do   # For each level gained in turn...
      # EXP Bar animation
      levelMinExp = growth_rate.minimum_exp_for_level(curLevel)
      levelMaxExp = growth_rate.minimum_exp_for_level(curLevel + 1)
      tempExp2 = (levelMaxExp<expFinal) ? levelMaxExp : expFinal
      pkmn.exp = tempExp2
      @scene.pbEXPBar(battler,levelMinExp,levelMaxExp,tempExp1,tempExp2)
      tempExp1 = tempExp2
      curLevel += 1
      if curLevel>newLevel
        # Gained all the Exp now, end the animation
        pkmn.calc_stats
        battler.pbUpdate(false) if battler
        @scene.pbRefreshOne(battler.index) if battler
        break
      end
      # Levelled up
      pbCommonAnimation("LevelUp",battler) if battler
      oldTotalHP = pkmn.totalhp
      oldAttack  = pkmn.attack
      oldDefense = pkmn.defense
      oldSpAtk   = pkmn.spatk
      oldSpDef   = pkmn.spdef
      oldSpeed   = pkmn.speed
      if battler && battler.pokemon
        battler.pokemon.changeHappiness("levelup")
      end
      pkmn.calc_stats
      battler.pbUpdate(false) if battler
      @scene.pbRefreshOne(battler.index) if battler
      pbDisplayPaused(_INTL("{1} subió a Lvl. {2}!",pkmn.name,curLevel))
      @scene.pbLevelUp(pkmn,battler,oldTotalHP,oldAttack,oldDefense,
                                    oldSpAtk,oldSpDef,oldSpeed)
      # Learn all moves learned at this level
      moveList = pkmn.getMoveList
      moveList.each { |m| pbLearnMove(idxParty,m[1]) if m[0]==curLevel }
    end
  end

  #=============================================================================
  # Learning a move
  #=============================================================================
  def pbLearnMove(idxParty,newMove)
    pkmn = pbParty(0)[idxParty]
    return if !pkmn
    pkmnName = pkmn.name
    battler = pbFindBattler(idxParty)
    moveName = GameData::Move.get(newMove).name
    # Pokémon already knows the move
    return if pkmn.hasMove?(newMove)
    # Pokémon has space for the new move; just learn it
    if pkmn.numMoves < Pokemon::MAX_MOVES
      pkmn.learn_move(newMove)
      pbDisplay(_INTL("{1} aprendió {2}!",pkmnName,moveName)) { pbSEPlay("Pkmn move learnt") }
      if battler
        battler.moves.push(PokeBattle_Move.from_pokemon_move(self, pkmn.moves.last))
        battler.pbCheckFormOnMovesetChange
      end
      return
    end
    # Pokémon already knows the maximum number of moves; try to forget one to learn the new move
    pbDisplayPaused(_INTL("{1} quiere aprender {2}, pero ya conoce {3} movimientos.",
       pkmnName, moveName, pkmn.numMoves.to_word))
    if pbDisplayConfirm(_INTL("¿Debería {1} olvidar un movimiento para aprender {2}?", pkmnName, moveName))
      loop do
        forgetMove = @scene.pbForgetMove(pkmn,newMove)
        if forgetMove>=0
          oldMoveName = pkmn.moves[forgetMove].name
          pkmn.moves[forgetMove] = Pokemon::Move.new(newMove)   # Replaces current/total PP
          battler.moves[forgetMove] = PokeBattle_Move.from_pokemon_move(self, pkmn.moves[forgetMove]) if battler
          pbDisplayPaused(_INTL("¡1, 2, y... ... ... Ta-da!")) { pbSEPlay("Battle ball drop") }
          pbDisplayPaused(_INTL("{1} olvidó cómo usar {2}. Y...",pkmnName,oldMoveName))
          pbDisplay(_INTL("{1} aprendió {2}!",pkmnName,moveName)) { pbSEPlay("Pkmn move learnt") }
          battler.pbCheckFormOnMovesetChange if battler
          break
        elsif pbDisplayConfirm(_INTL("¿No quieres aprender {1}?",moveName))
          pbDisplay(_INTL("{1} no aprendió {2}.",pkmnName,moveName))
          break
        end
      end
    else
      pbDisplay(_INTL("{1} no aprendió {2}.", pkmnName, moveName))
    end
  end
end
