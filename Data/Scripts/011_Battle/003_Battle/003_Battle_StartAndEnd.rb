class PokeBattle_Battle
  class BattleAbortedException < Exception; end

  def pbAbort
    raise BattleAbortedException.new("Battle aborted")
  end

  #=============================================================================
  # Makes sure all Pokémon exist that need to. Alter the type of battle if
  # necessary. Will never try to create battler positions, only delete them
  # (except for wild Pokémon whose number of positions are fixed). Reduces the
  # size of each side by 1 and tries again. If the side sizes are uneven, only
  # the larger side's size will be reduced by 1 each time, until both sides are
  # an equal size (then both sides will be reduced equally).
  #=============================================================================
  def pbEnsureParticipants
    # Prevent battles larger than 2v2 if both sides have multiple trainers
    # NOTE: This is necessary to ensure that battlers can never become unable to
    #       hit each other due to being too far away. In such situations,
    #       battlers will move to the centre position at the end of a round, but
    #       because they cannot move into a position owned by a different
    #       trainer, it's possible that battlers will be unable to move close
    #       enough to hit each other if there are multiple trainers on each
    #       side.
    if trainerBattle? && (@sideSizes[0]>2 || @sideSizes[1]>2) &&
       @player.length>1 && @opponent.length>1
      raise _INTL("Can't have battles larger than 2v2 where both sides have multiple trainers")
    end
    # Find out how many Pokémon each trainer has
    side1counts = pbAbleTeamCounts(0)
    side2counts = pbAbleTeamCounts(1)
    # Change the size of the battle depending on how many wild Pokémon there are
    if wildBattle? && side2counts[0]!=@sideSizes[1]
      if @sideSizes[0]==@sideSizes[1]
        # Even number of battlers per side, change both equally
        @sideSizes = [side2counts[0],side2counts[0]]
      else
        # Uneven number of battlers per side, just change wild side's size
        @sideSizes[1] = side2counts[0]
      end
    end
    # Check if battle is possible, including changing the number of battlers per
    # side if necessary
    loop do
      needsChanging = false
      for side in 0...2   # Each side in turn
        next if side==1 && wildBattle?   # Wild side's size already checked above
        sideCounts = (side==0) ? side1counts : side2counts
        requireds = []
        # Find out how many Pokémon each trainer on side needs to have
        for i in 0...@sideSizes[side]
          idxTrainer = pbGetOwnerIndexFromBattlerIndex(i*2+side)
          requireds[idxTrainer] = 0 if requireds[idxTrainer].nil?
          requireds[idxTrainer] += 1
        end
        # Compare the have values with the need values
        if requireds.length>sideCounts.length
          raise _INTL("Error: def pbGetOwnerIndexFromBattlerIndex gives invalid owner index ({1} for battle type {2}v{3}, trainers {4}v{5})",
             requireds.length-1,@sideSizes[0],@sideSizes[1],side1counts.length,side2counts.length)
        end
        sideCounts.each_with_index do |_count,i|
          if !requireds[i] || requireds[i]==0
            raise _INTL("Player-side trainer {1} has no battler position for their Pokémon to go (trying {2}v{3} battle)",
               i+1,@sideSizes[0],@sideSizes[1]) if side==0
            raise _INTL("Opposing trainer {1} has no battler position for their Pokémon to go (trying {2}v{3} battle)",
               i+1,@sideSizes[0],@sideSizes[1]) if side==1
          end
          next if requireds[i]<=sideCounts[i]   # Trainer has enough Pokémon to fill their positions
          if requireds[i]==1
            raise _INTL("Player-side trainer {1} has no able Pokémon",i+1) if side==0
            raise _INTL("Opposing trainer {1} has no able Pokémon",i+1) if side==1
          end
          # Not enough Pokémon, try lowering the number of battler positions
          needsChanging = true
          break
        end
        break if needsChanging
      end
      break if !needsChanging
      # Reduce one or both side's sizes by 1 and try again
      if wildBattle?
        PBDebug.log("#{@sideSizes[0]}v#{@sideSizes[1]} battle isn't possible " +
                    "(#{side1counts} player-side teams versus #{side2counts[0]} wild Pokémon)")
        newSize = @sideSizes[0]-1
      else
        PBDebug.log("#{@sideSizes[0]}v#{@sideSizes[1]} battle isn't possible " +
                    "(#{side1counts} player-side teams versus #{side2counts} opposing teams)")
        newSize = @sideSizes.max-1
      end
      if newSize==0
        raise _INTL("Couldn't lower either side's size any further, battle isn't possible")
      end
      for side in 0...2
        next if side==1 && wildBattle?   # Wild Pokémon's side size is fixed
        next if @sideSizes[side]==1 || newSize>@sideSizes[side]
        @sideSizes[side] = newSize
      end
      PBDebug.log("Trying #{@sideSizes[0]}v#{@sideSizes[1]} battle instead")
    end
  end

  #=============================================================================
  # Set up all battlers
  #=============================================================================
  def pbCreateBattler(idxBattler,pkmn,idxParty)
    if !@battlers[idxBattler].nil?
      raise _INTL("Battler index {1} already exists",idxBattler)
    end
    @battlers[idxBattler] = PokeBattle_Battler.new(self,idxBattler)
    @positions[idxBattler] = PokeBattle_ActivePosition.new
    pbClearChoice(idxBattler)
    @successStates[idxBattler] = PokeBattle_SuccessState.new
    @battlers[idxBattler].pbInitialize(pkmn,idxParty)
  end

  def pbSetUpSides
    ret = [[],[]]
    for side in 0...2
      # Set up wild Pokémon
      if side==1 && wildBattle?
        pbParty(1).each_with_index do |pkmn,idxPkmn|
          pbCreateBattler(2*idxPkmn+side,pkmn,idxPkmn)
          # Changes the Pokémon's form upon entering battle (if it should)
          @peer.pbOnEnteringBattle(self,pkmn,true)
          pbSetSeen(@battlers[2*idxPkmn+side])
          @usedInBattle[side][idxPkmn] = true
        end
        next
      end
      # Set up player's Pokémon and trainers' Pokémon
      trainer = (side==0) ? @player : @opponent
      requireds = []
      # Find out how many Pokémon each trainer on side needs to have
      for i in 0...@sideSizes[side]
        idxTrainer = pbGetOwnerIndexFromBattlerIndex(i*2+side)
        requireds[idxTrainer] = 0 if requireds[idxTrainer].nil?
        requireds[idxTrainer] += 1
      end
      # For each trainer in turn, find the needed number of Pokémon for them to
      # send out, and initialize them
      battlerNumber = 0
      trainer.each_with_index do |_t,idxTrainer|
        ret[side][idxTrainer] = []
        eachInTeam(side,idxTrainer) do |pkmn,idxPkmn|
          next if !pkmn.able?
          idxBattler = 2*battlerNumber+side
          pbCreateBattler(idxBattler,pkmn,idxPkmn)
          ret[side][idxTrainer].push(idxBattler)
          battlerNumber += 1
          break if ret[side][idxTrainer].length>=requireds[idxTrainer]
        end
      end
    end
    return ret
  end

  #=============================================================================
  # Send out all battlers at the start of battle
  #=============================================================================
  def pbStartBattleSendOut(sendOuts)
    # "Want to battle" messages
    if wildBattle?
      foeParty = pbParty(1)
      case foeParty.length
      when 1
        pbDisplayPaused(_INTL("¡Ojo! Un {1} salvaje ha aparecido!",foeParty[0].name))
      when 2
        pbDisplayPaused(_INTL("¡Ojo! Un {1} y un {2} han aparecido!",foeParty[0].name,
           foeParty[1].name))
      when 3
        pbDisplayPaused(_INTL("Oh! A wild {1}, {2} and {3} appeared!",foeParty[0].name,
           foeParty[1].name,foeParty[2].name))
      end
    else   # Trainer battle
      case @opponent.length
      when 1
        pbDisplayPaused(_INTL("¡{1} te desafía!",@opponent[0].full_name))
      when 2
        pbDisplayPaused(_INTL("¡{1} y {2} te desafían!",@opponent[0].full_name,
           @opponent[1].full_name))
      when 3
        pbDisplayPaused(_INTL("You are challenged by {1}, {2} and {3}!",
           @opponent[0].full_name,@opponent[1].full_name,@opponent[2].full_name))
      end
    end
    # Send out Pokémon (opposing trainers first)
    for side in [1,0]
      next if side==1 && wildBattle?
      msg = ""
      toSendOut = []
      trainers = (side==0) ? @player : @opponent
      # Opposing trainers and partner trainers's messages about sending out Pokémon
      trainers.each_with_index do |t,i|
        next if side==0 && i==0   # The player's message is shown last
        msg += "\r\n" if msg.length>0
        sent = sendOuts[side][i]
        case sent.length
        when 1
          msg += _INTL("{1} saca a {2}!",t.full_name,@battlers[sent[0]].name)
        when 2
          msg += _INTL("{1} saca a {2} y a {3}!",t.full_name,
             @battlers[sent[0]].name,@battlers[sent[1]].name)
        when 3
          msg += _INTL("{1} sacó a {2}, {3} y {4}!",t.full_name,
             @battlers[sent[0]].name,@battlers[sent[1]].name,@battlers[sent[2]].name)
        end
        toSendOut.concat(sent)
      end
      # The player's message about sending out Pokémon
      if side==0
        msg += "\r\n" if msg.length>0
        sent = sendOuts[side][0]
        case sent.length
        when 1
          msg += _INTL("¡Adelante! ¡{1}!",@battlers[sent[0]].name)
        when 2
          msg += _INTL("¡Adelante! ¡{1} y {2}!",@battlers[sent[0]].name,@battlers[sent[1]].name)
        when 3
          msg += _INTL("Go! {1}, {2} and {3}!",@battlers[sent[0]].name,
             @battlers[sent[1]].name,@battlers[sent[2]].name)
        end
        toSendOut.concat(sent)
      end
      pbDisplayBrief(msg) if msg.length>0
      # The actual sending out of Pokémon
      animSendOuts = []
      toSendOut.each do |idxBattler|
        animSendOuts.push([idxBattler,@battlers[idxBattler].pokemon])
      end
      pbSendOut(animSendOuts,true)
    end
  end

  #=============================================================================
  # Start a battle
  #=============================================================================
  def pbStartBattle
    PBDebug.log("")
    PBDebug.log("******************************************")
    logMsg = "[Started battle] "
    if @sideSizes[0]==1 && @sideSizes[1]==1
      logMsg += "Single "
    elsif @sideSizes[0]==2 && @sideSizes[1]==2
      logMsg += "Double "
    elsif @sideSizes[0]==3 && @sideSizes[1]==3
      logMsg += "Triple "
    else
      logMsg += "#{@sideSizes[0]}v#{@sideSizes[1]} "
    end
    logMsg += "wild " if wildBattle?
    logMsg += "trainer " if trainerBattle?
    logMsg += "battle (#{@player.length} trainer(s) vs. "
    logMsg += "#{pbParty(1).length} wild Pokémon)" if wildBattle?
    logMsg += "#{@opponent.length} trainer(s))" if trainerBattle?
    PBDebug.log(logMsg)
    pbEnsureParticipants
    begin
      pbStartBattleCore
    rescue BattleAbortedException
      @decision = 0
      @scene.pbEndBattle(@decision)
    end
    return @decision
  end

  def pbStartBattleCore
    # Set up the battlers on each side
    sendOuts = pbSetUpSides
    # Create all the sprites and play the battle intro animation
    @scene.pbStartBattle(self)
    # Show trainers on both sides sending out Pokémon
    pbStartBattleSendOut(sendOuts)
    # Weather announcement
    weather_data = GameData::BattleWeather.try_get(@field.weather)
    pbCommonAnimation(weather_data.animation) if weather_data
    case @field.weather
    when :Sun         then pbDisplay(_INTL("El sol pega fuerte."))
    when :Rain        then pbDisplay(_INTL("Está lloviendo."))
    when :Sandstorm   then pbDisplay(_INTL("Una tormenta de arena zarandea."))
    when :Hail        then pbDisplay(_INTL("Está nevando."))
    when :HarshSun    then pbDisplay(_INTL("El sol pega muy fuerte, parece Málaga."))
    when :HeavyRain   then pbDisplay(_INTL("Está lloviendo mucho."))
    when :StrongWinds then pbDisplay(_INTL("El viento pega fuerte."))
    when :ShadowSky   then pbDisplay(_INTL("El cielo está nublado."))
    when :Fog         then pbDisplay(_INTL("La niebla es espesa..."))
    end
    # Terrain announcement
    terrain_data = GameData::BattleTerrain.try_get(@field.terrain)
    pbCommonAnimation(terrain_data.animation) if terrain_data
    case @field.terrain
    when :Electric
      pbDisplay(_INTL("An electric current runs across the battlefield!"))
    when :Grassy
      pbDisplay(_INTL("Grass is covering the battlefield!"))
    when :Misty
      pbDisplay(_INTL("Mist swirls about the battlefield!"))
    when :Psychic
      pbDisplay(_INTL("The battlefield is weird!"))
    end
    # Abilities upon entering battle
    pbOnActiveAll
    # Main battle loop
    pbBattleLoop(sendOuts)
  end

  #=============================================================================
  # Main battle loop
  #=============================================================================
  def pbBattleLoop(sendOuts)
    @turnCount = 0
    @edaSpeak1 = true
    @edaSpeak2 = true

    @speak1 = true
    @speak2 = true


    if defined?(sendOuts) && sendOuts != nil
      sent = sendOuts[1][0]
      sent2 = sendOuts[1][1]

      echoln(sendOuts[1][0])
      echoln(sendOuts[1][1])
      
    end

    loop do   # Now begin the battle loop
      PBDebug.log("")
      PBDebug.log("***Round #{@turnCount+1}***")
      if @debug && @turnCount>=100
        @decision = pbDecisionOnTime
        PBDebug.log("")
        PBDebug.log("***Undecided after 100 rounds, aborting***")
        pbAbort
        break
      end
      
      # TIENES LA MÁSCARA DORADA ACTIVADA???
      if $PokemonBag.pbHasItem?(:GOLDENMASKON) && @turnCount == 0
        pbSEPlay("HAKI")
        pbDisplayPaused(_INTL('¡Se ha activado el poder de la máscara!'))

        @battlers[0].pbRaiseStatStage(:ATTACK ,1, @battlers[1])
        @battlers[0].pbRaiseStatStage(:SPECIAL_ATTACK ,1, @battlers[1])
      end

      # VS GABITE
      if $game_switches[2041] && @turnCount == 0 && @speak1
        pbDisplayPaused(_INTL('¡La furia de Gabite hace que su fuerza aumente!'))
        @battlers[1].pbRaiseStatStage(:ATTACK ,1, @battlers[1])
        @battlers[1].pbRaiseStatStage(:SPECIAL_ATTACK ,1, @battlers[1])
        @speak1 = false;
      end

      # VS RAIKOU
      if $game_switches[2042] && @turnCount == 0 && @speak1
        pbDisplayPaused(_INTL('¡La furia de Raikou hace que su fuerza aumente!'))
        @battlers[1].pbRaiseStatStage(:ATTACK ,1, @battlers[1])
        @battlers[1].pbRaiseStatStage(:SPECIAL_ATTACK ,1, @battlers[1])
        @speak1 = false;
      end

      # VS TAPUS
      if $game_switches[2045] && @turnCount == 4
        pbSEPlay("darek_hum")
        ChangeSpeed.new.pbChangeSpeed(0)
        pbDisplayPaused(_INTL('???: ¡Detened la pelea ahora mismo!'))
        pbAbort
      end

      if defined?(sent) && sent != nil

        # 1R COMBATE CONTRA EDA
        if $game_switches[2002] && @turnCount == 1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Eda: ¡Auch! ¡Eso nos hizo daño!'))
          @scene.pbShowOpponent(1)
        end

        # 1R COMBATE CONTRA DAREK
        if $game_switches[2003] && @turnCount == 1 
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Darek: ¡Oye, menudo golpe nos has dado!'))
          @scene.pbShowOpponent(1)
        end

        # 1R COMBATE CONTRA SILVANO
        if $game_switches[2004] && @battlers[sent[0]].species == :THWACKEY && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Silvano: ¡Este combate se está volviendo muy salvaje!'))
          pbWait(3)
          pbDisplayPaused(_INTL('Silvano: ¡Vamos a darlo todo!'))
          @scene.pbShowOpponent(1)
          @speak1 = false
        end

        # 1R COMBATE CONTRA VESTA
        if $game_switches[2005] && @battlers[sent[0]].species == :SALAZZLE && @speak1
          @scene.pbShowOpponent(0)
          if $game_variables[101] == 0
            pbDisplayPaused(_INTL('Vesta: ¡No te lo creas tanto, mocoso!'))
          else
            pbDisplayPaused(_INTL('Vesta: ¡No te lo creas tanto, mocosa!'))
          end
          pbWait(3)
          pbDisplayPaused(_INTL('Vesta: ¡Vas a conocer el verdadero poder de la Familia Real!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # 1R COMBATE CONTRA XIAO
        if $game_switches[2006] && @battlers[sent[0]].species == :LUCARIO && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Yang Xiao: ¡Junto a Lucario, no puedo perder!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # 2ND COMBATE CONTRA DAREK
        if $game_switches[2007] && @battlers[sent[0]].species == :GROVYLE && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Darek: ¡Vas a ver lo mucho que he mejorado!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # 2ND COMBATE CONTRA VESTA
        if $game_switches[2008] && @battlers[sent[0]].species == :SALAZZLE && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Vesta: ¡Esta vez voy con todo, os vais a enterar!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # 1R COMBATE CONTRA CONTRAPARTE DE GÉNERO
        if $game_switches[2009] && @battlers[sent[0]].species == :MARSHTOMP && @speak1
          @scene.pbShowOpponent(0)
          if $game_variables[101] == 0
            pbDisplayPaused(_INTL('Lluvia: ¡No soy una novata, no te confíes!'))
          else
            pbDisplayPaused(_INTL('Adrián: ¡No soy un novato, no te confíes!'))
          end
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA CELESTE
        if $game_switches[2010] && @battlers[sent[0]].species == :MILOTIC && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Celeste: ¡Junto a Milotic, puedo surfear en cualquier situación!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA MAJIME
        if $game_switches[2011] && @battlers[sent[0]].species == :SEVIPER && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Majime: Una ninja jamás pierde la calma, pero es el momento de enseñarte mi verdadero poder.'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA SAKURA
        if $game_switches[2012] && @battlers[sent[0]].species == :MAWILE && @speak1
          @scene.pbShowOpponent(0)
          pbSEPlay("sakura_molesta")
          pbDisplayPaused(_INTL('Sakura: ¡Te vamos a mostrar nuestra verdadera cara!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # 1R COMBATE CONTRA ANGIE
        if $game_switches[2013] && @turnCount == 3 && @speak1
          @scene.pbShowOpponent(0)
          pbSEPlay("Angie_yash")
          pbDisplayPaused(_INTL('Angie Stones: ¿Todo bien? ¡Veo que no eres capaz de aguantar mis chispas, crack!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # 1R COMBATE CONTRA ANGIE
        if $game_switches[2013] && @turnCount == 8 && @speak2
          @scene.pbShowOpponent(0)
          pbSEPlay("Angie_risa")
          pbDisplayPaused(_INTL('Angie Stones: ¡No puedes vencerme!'))
          pbAbort
          @speak2 = false;
        end

        # COMBATE CONTRA AGAPITO
        if $game_switches[2014] && @battlers[sent[0]].species == :GOLISOPOD && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Agapito: ¡No dejaré que salgáis de aquí, por doña Brenda!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA BRENDA
        if $game_switches[2015] && @battlers[sent[0]].species == :CERULEDGE && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Jefa Brenda: ¡La justicia caerá sobre ti, no perdonaré el daño que le habéis hecho a mi Teniente!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # 2ND COMBATE CONTRA CONTRAPARTE DE GÉNERO
        if $game_switches[2016] && @battlers[sent[0]].species == :SWAMPERT && @speak1
          @scene.pbShowOpponent(0)
          if $game_variables[101] == 0
            pbDisplayPaused(_INTL('Lluvia: ¡Sigo siendo la alumna prodigio, no te lo pondré fácil, {1}!', pbPlayer.name))
          else
            pbDisplayPaused(_INTL('Adrián: ¡Sigo siendo el alumno prodigio, no te lo pondré fácil!, {1}!', pbPlayer.name))
          end
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA ZURVAN
        if $game_switches[2017] && @battlers[sent[0]].species == :GENGAR && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Zurvan: El futuro está escrito... ¿Serás capaz de cambiarlo?'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA HAKAN
        if $game_switches[2018] && @battlers[sent[0]].species == :VENUSAUR && @speak1
          @scene.pbShowOpponent(0)
          pbSEPlay("Hakan_risa")
          pbDisplayPaused(_INTL('Hakan: ¡Una rubia de ciudad, jamás podrá derrotar al Rey de la Jungla!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA SHADOW
        if $game_switches[2019] && @battlers[sent[0]].species == :BANETTE && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Shadow: ¡Sí... ese es el poder que esperaba ver en ti! ¡Voy a arrebatar tu cuerpo! ¡Shi, shi, shi!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA BRENDA 2
        if $game_switches[2020] && @battlers[sent[0]].species == :CERULEDGE && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Jefa Brenda: ¡¿Cómo se te ocurre meterte en medio de una ejecución?!'))
          pbWait(3)
          pbDisplayPaused(_INTL('Jefa Brenda: ¡La justicia caerá sobre ti!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA EDWARD
        if $game_switches[2021] && @turnCount == 3 && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Edward: Te veo en problemas, Eda...'))
          pbWait(3)
          pbDisplayPaused(_INTL('Edward: ¿Entiendes ahora el poder que posee la Familia Real?'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA WILLIAM
        if $game_switches[2022] && @battlers[sent[0]].species == :MACHAMP && @speak1
          @scene.pbShowOpponent(0)
          pbSEPlay("william_asentir")
          pbDisplayPaused(_INTL('William: All right, let\'s finish this.'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end


        # FORZAR FIN COMBATE CON ANGIE
        if @turnCount >= 3 && $game_switches[886]
          #pbCreateBattler(2*idxPkmn+side,pkmn,idxPkmn)
          @scene.pbShowOpponent(0)
          pbWait(10)
          pbDisplayPaused(_INTL('Angie: ¡Ey, parece que tenemos visita!'))
          pbAbort
        end


          # COMBATE CON EDA
          if @battlers[sent[0]].name == "Chic" && $game_switches[942] && @edaSpeak1
            pbWait(10)
            @scene.pbShowOpponent(0)
            pbSEPlay("eda_risa2")
            pbDisplayPaused(_INTL('Eda: ¡Vamos a demostrarle lo mucho que hemos mejorado, Chic!'))
            @scene.pbShowOpponent(1)
            @edaSpeak1 = false
          end

          if @battlers[sent[0]].name == "Latias" && $game_switches[942] && @edaSpeak2
            pbWait(10)
            @scene.pbShowOpponent(0)
            pbSEPlay("eda_risa")
            pbDisplayPaused(_INTL('Eda: ¡Toca sacar a mi arma secreta, Latias!'))
            @scene.pbShowOpponent(1)
            @edaSpeak2 = false
          end

          # COMBATE CON DYNAMO
          if $game_switches[1179]
            if @turnCount == 0
              #@sprites = {}
              #@viewport = Viewport.new(0,0, Graphics.width, Graphics.height)
              #@viewport.z = 99999
              #@sprites["pista"] = AnimatedSprite.new("Graphics/Pictures/escena2",8,512,384,2,@viewport)
              #pbFadeInAndShow(@sprites)

              @scene.pbShowOpponent(0)
              pbDisplayPaused(_INTL('Dynamó: ¡Que se active el poder de la Máscara Dorada!'))
              @scene.pbShowOpponent(1)
              pbDisplayPaused(_INTL('Kaleo: ¡AAAAARG!'))
              @scene.pbShowOpponent(2)

              @battlers[sent[0]].pbRaiseStatStage(:ATTACK ,1,@battlers[sent[0]])
              @battlers[sent[0]].pbRaiseStatStage(:SPECIAL_ATTACK ,1,@battlers[sent[0]])

              @battlers[sent2[0]].pbRaiseStatStage(:ATTACK ,1,@battlers[sent[0]])
              @battlers[sent2[0]].pbRaiseStatStage(:SPECIAL_ATTACK ,1,@battlers[sent[0]])

              #puts @battlers[sent[0]].species
              #puts @battlers[sent2[0]].species



              #pbFadeOutAndHide(@sprites)
              #@scene.pbShowOpponent(1)
            end
          end


          #COMABTE CONTRA PLAYER
          if @battlers[sent[0]].species == :LUCARIO && $game_switches[1180]
            @scene.pbShowOpponent(0)
            pbWait(10)
            pbDisplayPaused(_INTL("¡{1}: ¡¿Qué estás haciendo, Lucario?!",@opponent[0].name))
            $game_switches[742] = true
            pbWait(5)
            pbDisplayPaused(_INTL("¡{1}: ¡Ataca de una vez!",@opponent[0].name))
            pbAbort
          end

          # COMBATE CONTRA ESTELA
          if $game_switches[2024] && @battlers[sent[0]].species == :TYRANITAR && @speak1
            @scene.pbShowOpponent(0)
            pbSEPlay("estela_risa_2")
            pbDisplayPaused(_INTL('Estela: ¡Buen intento, {1}, pero el reinicio del universo llegará, da igual lo que hagas!', pbPlayer.name))
            @scene.pbShowOpponent(1)
            @speak1 = false;
          end

          # COMBATE CONTRA ESTELA 2
          if $game_switches[2024] && @turnCount == 8 && @speak2
            @scene.pbShowOpponent(0)
            pbSEPlay("estela_suspiro")
            pbDisplayPaused(_INTL('Estela: Esto es totalmente inútil, es una pérdida de tiempo...'))
            pbAbort
            @speak2 = false;
          end

          # COMBATE CONTRA LIBERTY
          if $game_switches[2025] && @turnCount == 0 && @speak1
            @scene.pbShowOpponent(0)
            pbSEPlay("risa_liberty")
            pbDisplayPaused(_INTL('Liberty: ¡Ja, já! ¡Vamos con todo desde el inicio!'))
            @scene.pbShowOpponent(1)
            @speak1 = false;
          end

          # COMBATE CONTRA LIBERTY 2
          if $game_switches[2025] && @battlers[sent[0]].species == :VICTINI && @speak2
            @scene.pbShowOpponent(0)
            pbSEPlay("risa_liberty")
            pbDisplayPaused(_INTL('Liberty: ¡Ja, já! ¡Adelante, Victini, la victoria es nuestra!'))
            @scene.pbShowOpponent(1)
            @speak2 = false;
          end

          # COMBATE CONTRA SHAYAN
          if $game_switches[2026] && @battlers[sent[0]].species == :HERACROSS && @speak1
            @scene.pbShowOpponent(0)
            pbDisplayPaused(_INTL('Shayan: ¡Seré capaz de proteger la aldea, cueste lo que cueste!'))
            @scene.pbShowOpponent(1)
            @speak1 = false;
          end

          # COMBATE CONTRA HAKAN
          if $game_switches[2027] && @battlers[sent[0]].species == :ANNIHILAPE && @speak1
            @scene.pbShowOpponent(0)
            pbDisplayPaused(_INTL('Hakan: ¡Está... Está sucediendo de nuevo!'))
            @scene.pbShowOpponent(1)
            @speak1 = false;
          end

        # COMBATE CONTRA MAJIME
        if $game_switches[2028] && @battlers[sent[0]].species == :SEVIPER && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Majime: ¡Debo... Debo llevarte conmigo! ¡No puedo quedar mal otra vez!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA DIOS DE LOS CANELONES
        if $game_switches[2029] && @battlers[sent[0]].species == :SNORLAX && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Dios de los canelones: ¡Diooos, realmente nos está entrando hambre con este combate!'))
          @battlers[sent[0]].pbRaiseStatStage(:DEFENSE ,1,@battlers[sent[0]])
          @battlers[sent[0]].pbRaiseStatStage(:SPECIAL_DEFENSE ,1,@battlers[sent[0]])
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA HENRY Y AMATISTA
        if $game_switches[2030] && @turnCount == 8 && @speak1
          @scene.pbShowOpponent(0)
          pbSEPlay("ara araaaa")
          pbDisplayPaused(_INTL('Amatista: Ara, ara... ¿Todavía no se rinden?'))
          @scene.pbShowOpponent(1)
          pbSEPlay("shout")
          pbDisplayPaused(_INTL('Henry: Maditos Wright... ¡Acabaré con vuestra existencia!'))
          @scene.pbShowOpponent(2)
          @battlers[sent[0]].pbRaiseStatStage(:ATTACK ,1,@battlers[sent[0]])
          @battlers[sent[0]].pbRaiseStatStage(:SPECIAL_ATTACK ,1,@battlers[sent[0]])

          @battlers[sent2[0]].pbRaiseStatStage(:ATTACK ,1,@battlers[sent[0]])
          @battlers[sent2[0]].pbRaiseStatStage(:SPECIAL_ATTACK ,1,@battlers[sent[0]])
          @speak1 = false;
        end

        # COMBATE CONTRA EDA FINAL
        if $game_switches[2031] && @battlers[sent[0]].species == :BLAZIKEN && @speak1
          @scene.pbShowOpponent(0)
          pbSEPlay("eda_risa2")
          pbDisplayPaused(_INTL('Eda: ¡Vamos darlo todo, Chic!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA DAREK FINAL
        if $game_switches[2032] && @battlers[sent[0]].species == :SCEPTILE && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Darek: ¡Vamos a demostrarle nuestra afinidad, Sceptile!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA PETRA
        if $game_switches[2033] && @battlers[sent[0]].species == :AERODACTYL && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Petra: ¡Es hora de enseñarle el temario de nuestra escuela!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA MARCIAL
        if $game_switches[2034] && @battlers[sent[0]].species == :MEDICHAM && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Marcial: ¡Es hora de poner la ola a mi favor!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA ERICO
        if $game_switches[2035] && @battlers[sent[0]].species == :MANECTRIC && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Erico: ¡Es hora de dar nuestra mayor descarga!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA CANDELA
        if $game_switches[2036] && @battlers[sent[0]].species == :CAMERUPT && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Candela: ¡Estás "On fire"! ¡Déjame mostrarte la llama de nuestra pasión!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA NORMAN
        if $game_switches[2037] && @battlers[sent[0]].species == :KANGASKHAN && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Norman: ¡Te demostraré la fuerza del padre de un Campeón!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA ALANA
        if $game_switches[2038] && @battlers[sent[0]].species == :ALTARIA && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Alana: ¡Es hora de despegar, alcemos el vuelo!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA VITO Y LETI
        if $game_switches[2039] && @battlers[sent[0]].species == :GALLADE && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Vito: ¿Estás lista, hermanita?'))
          @scene.pbShowOpponent(1)
          pbDisplayPaused(_INTL('Leti: ¡Estás tardando en megaevolucionar, hermanito!'))
          @scene.pbShowOpponent(2)
          @speak1 = false;
        end

        # COMBATE CONTRA PLUBIO
        if $game_switches[2040] && @battlers[sent[0]].species == :SHARPEDO && @speak1
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Plubio: ¡Vamos a demostrarle porqué fuimos Campeones!'))
          @scene.pbShowOpponent(1)
          @speak1 = false;
        end

        # COMBATE CONTRA DYNAMÓ FINAL
        if $game_switches[2043] && @turnCount == 0
          @scene.pbShowOpponent(0)
          pbSEPlay("Dynamo_risa")
          pbDisplayPaused(_INTL('Dynamó: ¡Que se active el poder de la máscara!'))
          @scene.pbShowOpponent(1)
          @battlers[sent[0]].pbRaiseStatStage(:ATTACK ,1,@battlers[sent[0]])
          @battlers[sent[0]].pbRaiseStatStage(:SPECIAL_ATTACK ,1,@battlers[sent[0]])
        end

        # COMBATE CONTRA DYNAMÓ FINAL
        if $game_switches[2043] && @battlers[sent[0]].species == :GRIMMSNARL && @speak2
          @scene.pbShowOpponent(0)
          pbDisplayPaused(_INTL('Dynamó: ¡Estoy harto de que se burlen de mí, te vas a enterar!'))
          @scene.pbShowOpponent(1)
          @speak2 = false;
        end

        # 1R COMBATE CONTRA SOPHIE
        if $game_switches[2046] && @turnCount == 8
          pbSEPlay("shout")
          pbDisplayPaused(_INTL('William: Sophie! Get out of there, now!'))
          pbAbort
          @speak2 = false;
        end


      end

      PBDebug.log("")
      # Command phase
      PBDebug.logonerr { pbCommandPhase }
      break if @decision>0
      # Attack phase
      PBDebug.logonerr { pbAttackPhase }
      break if @decision>0
      # End of round phase
      PBDebug.logonerr { pbEndOfRoundPhase }
      break if @decision>0
      @turnCount += 1
    end
    pbEndOfBattle
  end

  #=============================================================================
  # End of battle
  #=============================================================================
  def pbGainMoney
    return if !@internalBattle || !@moneyGain
    # Money rewarded from opposing trainers
    if trainerBattle?
      tMoney = 0
      @opponent.each_with_index do |t,i|
        tMoney += pbMaxLevelInTeam(1, i) * t.base_money
      end

      #echoln @field.effects[PBEffects::GoldenCoco]
      echoln $game_switches[90]

      tMoney *= 2 if @field.effects[PBEffects::AmuletCoin]
      tMoney *= 2 if @field.effects[PBEffects::HappyHour]
      #tMoney *= 2 if @field.effects[PBEffects::GoldenCoco]

      tMoney *= 2 if $game_switches[90]

      oldMoney = pbPlayer.money
      pbPlayer.money += tMoney
      moneyGained = pbPlayer.money-oldMoney
      if moneyGained>0
        pbDisplayPaused(_INTL("¡Ganaste ${1} por tu victoria!",moneyGained.to_s_formatted))
      end
    end
    # Pick up money scattered by Pay Day
    if @field.effects[PBEffects::PayDay]>0
      @field.effects[PBEffects::PayDay] *= 2 if @field.effects[PBEffects::AmuletCoin]
      @field.effects[PBEffects::PayDay] *= 2 if @field.effects[PBEffects::HappyHour]
      oldMoney = pbPlayer.money
      pbPlayer.money += @field.effects[PBEffects::PayDay]
      moneyGained = pbPlayer.money-oldMoney
      if moneyGained>0
        pbDisplayPaused(_INTL("Recogiste ${1}!",moneyGained.to_s_formatted))
      end
    end
  end

  def pbLoseMoney
    return if !@internalBattle || !@moneyGain
    return if $game_switches[Settings::NO_MONEY_LOSS]
    maxLevel = pbMaxLevelInTeam(0,0)   # Player's Pokémon only, not partner's
    multiplier = [8,16,24,36,48,64,80,100,120]
    idxMultiplier = [pbPlayer.badge_count, multiplier.length - 1].min
    tMoney = maxLevel*multiplier[idxMultiplier]
    tMoney = pbPlayer.money if tMoney>pbPlayer.money
    oldMoney = pbPlayer.money
    pbPlayer.money -= tMoney
    moneyLost = oldMoney-pbPlayer.money
    if moneyLost>0
      if trainerBattle?
        pbDisplayPaused(_INTL("Le diste ${1} al ganador...",moneyLost.to_s_formatted))
      else
        pbDisplayPaused(_INTL("Has paniqueado y se te han caído ${1}...",moneyLost.to_s_formatted))
      end
    end
  end

  def pbEndOfBattle
    oldDecision = @decision
    @decision = 4 if @decision==1 && wildBattle? && @caughtPokemon.length>0
    case oldDecision
    ##### WIN #####
    when 1
      PBDebug.log("")
      PBDebug.log("***Player won***")
      if trainerBattle?
        @scene.pbTrainerBattleSuccess
        case @opponent.length
        when 1
          pbDisplayPaused(_INTL("¡Has vencido a {1}!",@opponent[0].full_name))
        when 2
          pbDisplayPaused(_INTL("¡Has vencido a {1} y a {2}!",@opponent[0].full_name,
             @opponent[1].full_name))
        when 3
          pbDisplayPaused(_INTL("You defeated {1}, {2} and {3}!",@opponent[0].full_name,
             @opponent[1].full_name,@opponent[2].full_name))
        end
        @opponent.each_with_index do |_t,i|
          @scene.pbShowOpponent(i)
          msg = (@endSpeeches[i] && @endSpeeches[i]!="") ? @endSpeeches[i] : "..."
          pbDisplayPaused(msg.gsub(/\\[Pp][Nn]/,pbPlayer.name))
        end
      end
      # Gain money from winning a trainer battle, and from Pay Day
      pbGainMoney if @decision!=4
      # Hide remaining trainer
      @scene.pbShowOpponent(@opponent.length) if trainerBattle? && @caughtPokemon.length>0
    ##### LOSE, DRAW #####
    when 2, 5
      PBDebug.log("")
      PBDebug.log("***Player lost***") if @decision==2
      PBDebug.log("***Player drew with opponent***") if @decision==5
      if @internalBattle
        pbDisplayPaused(_INTL("¡No te quedan Pokémon para pelear!"))
        if trainerBattle?
          case @opponent.length
          when 1
            pbDisplayPaused(_INTL("¡Has perdido contra {1}!",@opponent[0].full_name))
          when 2
            pbDisplayPaused(_INTL("¡Has perdido contra {1} y {2}!",
               @opponent[0].full_name,@opponent[1].full_name))
          when 3
            pbDisplayPaused(_INTL("You lost against {1}, {2} and {3}!",
               @opponent[0].full_name,@opponent[1].full_name,@opponent[2].full_name))
          end
        end
        # Lose money from losing a battle
        pbLoseMoney
        pbDisplayPaused(_INTL("¡Fuiste corriendo al Centro Pokémon!")) if !@canLose && !$game_switches[1526]
      elsif @decision==2
        if @opponent
          @opponent.each_with_index do |_t,i|
            @scene.pbShowOpponent(i)
            msg = (@endSpeechesWin[i] && @endSpeechesWin[i]!="") ? @endSpeechesWin[i] : "..."
            pbDisplayPaused(msg.gsub(/\\[Pp][Nn]/,pbPlayer.name))
          end
        end
      end
    ##### CAUGHT WILD POKÉMON #####
    when 4
      @scene.pbWildBattleSuccess if !Settings::GAIN_EXP_FOR_CAPTURE
    end
    # Register captured Pokémon in the Pokédex, and store them
    pbRecordAndStoreCaughtPokemon
    # Collect Pay Day money in a wild battle that ended in a capture
    pbGainMoney if @decision==4
    # Pass on Pokérus within the party
    if @internalBattle
      infected = []
      $Trainer.party.each_with_index do |pkmn,i|
        infected.push(i) if pkmn.pokerusStage==1
      end
      infected.each do |idxParty|
        strain = $Trainer.party[idxParty].pokerusStrain
        if idxParty>0 && $Trainer.party[idxParty-1].pokerusStage==0
          $Trainer.party[idxParty-1].givePokerus(strain) if rand(3)==0   # 33%
        end
        if idxParty<$Trainer.party.length-1 && $Trainer.party[idxParty+1].pokerusStage==0
          $Trainer.party[idxParty+1].givePokerus(strain) if rand(3)==0   # 33%
        end
      end
    end
    # Clean up battle stuff
    @scene.pbEndBattle(@decision)
    @battlers.each do |b|
      next if !b
      pbCancelChoice(b.index)   # Restore unused items to Bag
      BattleHandlers.triggerAbilityOnSwitchOut(b.ability,b,true) if b.abilityActive?
    end
    pbParty(0).each_with_index do |pkmn,i|
      next if !pkmn
      @peer.pbOnLeavingBattle(self,pkmn,@usedInBattle[0][i],true)   # Reset form
      pkmn.item = @initialItems[0][i]
    end
    return @decision
  end

  #=============================================================================
  # Judging
  #=============================================================================
  def pbJudgeCheckpoint(user,move=nil); end

  def pbDecisionOnTime
    counts   = [0,0]
    hpTotals = [0,0]
    for side in 0...2
      pbParty(side).each do |pkmn|
        next if !pkmn || !pkmn.able?
        counts[side]   += 1
        hpTotals[side] += pkmn.hp
      end
    end
    return 1 if counts[0]>counts[1]       # Win (player has more able Pokémon)
    return 2 if counts[0]<counts[1]       # Loss (foe has more able Pokémon)
    return 1 if hpTotals[0]>hpTotals[1]   # Win (player has more HP in total)
    return 2 if hpTotals[0]<hpTotals[1]   # Loss (foe has more HP in total)
    return 5                              # Draw
  end

  # Unused
  def pbDecisionOnTime2
    counts   = [0,0]
    hpTotals = [0,0]
    for side in 0...2
      pbParty(side).each do |pkmn|
        next if !pkmn || !pkmn.able?
        counts[side]   += 1
        hpTotals[side] += 100*pkmn.hp/pkmn.totalhp
      end
      hpTotals[side] /= counts[side] if counts[side]>1
    end
    return 1 if counts[0]>counts[1]       # Win (player has more able Pokémon)
    return 2 if counts[0]<counts[1]       # Loss (foe has more able Pokémon)
    return 1 if hpTotals[0]>hpTotals[1]   # Win (player has a bigger average HP %)
    return 2 if hpTotals[0]<hpTotals[1]   # Loss (foe has a bigger average HP %)
    return 5                              # Draw
  end

  def pbDecisionOnDraw; return 5; end     # Draw

  def pbJudge
    fainted1 = pbAllFainted?(0)
    fainted2 = pbAllFainted?(1)
    if fainted1 && fainted2; @decision = pbDecisionOnDraw   # Draw
    elsif fainted1;          @decision = 2                  # Loss
    elsif fainted2;          @decision = 1                  # Win
    end
  end
end
