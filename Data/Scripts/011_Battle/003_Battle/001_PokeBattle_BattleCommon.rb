module PokeBattle_BattleCommon
  #=============================================================================
  # Store caught Pokémon
  #=============================================================================
  def pbStorePokemon(pkmn)
    # Nickname the Pokémon (unless it's a Shadow Pokémon)
    if !pkmn.shadowPokemon?
      if pbDisplayConfirm(_INTL("¿Quieres darle un mote a {1}?", pkmn.name))
        nickname = @scene.pbNameEntry(_INTL("¿Mote de {1}?", pkmn.speciesName), pkmn)
        pkmn.name = nickname
      end
    end
    # Store the Pokémon
    currentBox = @peer.pbCurrentBox
    storedBox  = @peer.pbStorePokemon(pbPlayer,pkmn)
    if storedBox<0
      pbDisplayPaused(_INTL("¡{1} ha sido añadido a tu equipo!",pkmn.name))
      @initialItems[0][pbPlayer.party.length-1] = pkmn.item_id if @initialItems
      return
    end
    # Messages saying the Pokémon was stored in a PC box
    creator    = @peer.pbGetStorageCreatorName
    curBoxName = @peer.pbBoxName(currentBox)
    boxName    = @peer.pbBoxName(storedBox)
    if storedBox!=currentBox
      if creator
        pbDisplayPaused(_INTL("Box \"{1}\" on {2}'s PC was full.",curBoxName,creator))
      else
        pbDisplayPaused(_INTL("Box \"{1}\" on someone's PC was full.",curBoxName))
      end
      pbDisplayPaused(_INTL("{1} fue transferido a la caja \"{2}\".",pkmn.name,boxName))
    else
      if creator
        pbDisplayPaused(_INTL("{1} fue transferido al PC de {2}.",pkmn.name,creator))
      else
        pbDisplayPaused(_INTL("{1} fue transferido al PC de algiuen.",pkmn.name))
      end
      pbDisplayPaused(_INTL("It was stored in box \"{1}\".",boxName))
    end
  end

  # Register all caught Pokémon in the Pokédex, and store them.
  def pbRecordAndStoreCaughtPokemon
    @caughtPokemon.each do |pkmn|
      # In case the form changed upon leaving battle
      pbPlayer.pokedex.register(pkmn)
      pbSetBattled(pkmn)
      # Record the Pokémon's species as owned in the Pokédex
      if !pbPlayer.owned?(pkmn.species)
        pbPlayer.pokedex.set_owned(pkmn.species)
        if $Trainer.has_pokedex
          pbDisplayPaused(_INTL("Los datos de {1} han sido añadidos a la Pokédex!",pkmn.name))
          pbPlayer.pokedex.register_last_seen(pkmn)
          @scene.pbShowPokedex(pkmn.species)
        end
      end
      # Record a Shadow Pokémon's species as having been caught
      pbPlayer.pokedex.set_shadow_pokemon_owned(pkmn.species) if pkmn.shadowPokemon?
      # Store caught Pokémon
      pbStorePokemon(pkmn)
    end
    @caughtPokemon.clear
  end

  #=============================================================================
  # Throw a Poké Ball
  #=============================================================================
  def pbThrowPokeBall(idxBattler,ball,catch_rate=nil,showPlayer=false)
    # Determine which Pokémon you're throwing the Poké Ball at
    battler = nil
    if opposes?(idxBattler)
      battler = @battlers[idxBattler]
    else
      battler = @battlers[idxBattler].pbDirectOpposing(true)
    end
    if battler.fainted?
      battler.eachAlly do |b|
        battler = b
        break
      end
    end
    # Messages
    itemName = GameData::Item.get(ball).name
    if battler.fainted?
      if itemName.starts_with_vowel?
        pbDisplay(_INTL("{1} threw a {2}!",pbPlayer.name,itemName))
      else
        pbDisplay(_INTL("{1} threw a {2}!",pbPlayer.name,itemName))
      end
      pbDisplay(_INTL("Pero no había objetivo..."))
      return
    end
    if itemName.starts_with_vowel?
      pbDisplayBrief(_INTL("{1} threw an {2}!",pbPlayer.name,itemName))
    else
      pbDisplayBrief(_INTL("{1} threw a {2}!",pbPlayer.name,itemName))
    end
    # Animation of opposing trainer blocking Poké Balls (unless it's a Snag Ball
    # at a Shadow Pokémon)

    if trainerBattle? && !(GameData::Item.get(ball).is_snag_ball? && battler.shadowPokemon?)
      	@scene.pbThrowAndDeflect(ball,1)
      	pbDisplay(_INTL("¡El entrenador ha bloqueado la Pokéball! ¡No me seas puerco!"))
      	return
    end

    if $game_switches[999] == true
	    @scene.pbThrowAndDeflect(ball,1)
	    pbDisplay(_INTL("¡El Pokémon pertenece a un Entrenador! ¡No me seas puerco!"))
      return
    end

    if $game_switches[2096] == true && pbPlayer.owned?(battler.species)
	    @scene.pbThrowAndDeflect(ball,1)
	    pbDisplay(_INTL("¡No puedes atrapar la misma línea evolutiva por segunda vez en modo Radical!"))
      return
    end

    return if defined?(Settings::ZUD_COMPAT) && _ZUD_RaidCaptureFail(battler,ball)
    # Calculate the number of shakes (4=capture)
    pkmn = battler.pokemon
    @criticalCapture = false
    numShakes = pbCaptureCalc(pkmn,battler,catch_rate,ball)
    PBDebug.log("[Threw Poké Ball] #{itemName}, #{numShakes} shakes (4=capture)")
    # Animation of Ball throw, absorb, shake and capture/burst out
    @scene.pbThrow(ball,numShakes,@criticalCapture,battler.index,showPlayer)
    # Ball Fetch
    if numShakes != 4 && ![:SAFARIBALL,:MASTERBALL].include?(ball)
      eachBattler do |b|
        next if !b.hasActiveAbility?(:BALLFETCH) || b.item
        b.effects[PBEffects::BallFetch] = ball
        break
      end
    end
    # Outcome message
    case numShakes
    when 0
      pbDisplay(_INTL("¡Oh no! ¡El Pokémon se ha escapado!"))
      BallHandlers.onFailCatch(ball,self,battler)
    when 1
      pbDisplay(_INTL("¡Damn! ¡Parecía que se había atrapado!"))
      BallHandlers.onFailCatch(ball,self,battler)
    when 2
      pbDisplay(_INTL("¡Aargh! ¡Casi lo tenías!"))
      BallHandlers.onFailCatch(ball,self,battler)
    when 3
      pbDisplay(_INTL("¡Diooos! ¡Eso estuvo muy cerca!"))
      BallHandlers.onFailCatch(ball,self,battler)
    when 4
      pbDisplayBrief(_INTL("¡Gotcha! ¡{1} ha sido capturado!",pkmn.name))
      @scene.pbThrowSuccess   # Play capture success jingle
      pbRemoveFromParty(battler.index,battler.pokemonIndex)
      # Gain Exp
      if Settings::GAIN_EXP_FOR_CAPTURE
        battler.captured = true
        pbGainExp
        battler.captured = false
      end
      battler.pbReset
      if pbAllFainted?(battler.index)
        @decision = (trainerBattle?) ? 1 : 4   # Battle ended by win/capture
      end
      # Modify the Pokémon's properties because of the capture
      if GameData::Item.get(ball).is_snag_ball?
        pkmn.owner = Pokemon::Owner.new_from_trainer(pbPlayer)
      end
      BallHandlers.onCatch(ball,self,pkmn)
      pkmn.poke_ball = ball
      pkmn.makeUnmega if pkmn.mega?
      pkmn.makeUnprimal
      pkmn.update_shadow_moves if pkmn.shadowPokemon?
      pkmn.record_first_moves
      # Reset form
      pkmn.forced_form = nil if MultipleForms.hasFunction?(pkmn.species,"getForm")
      @peer.pbOnLeavingBattle(self,pkmn,true,true)
      # Make the Poké Ball and data box disappear
      @scene.pbHideCaptureBall(idxBattler)
      # Save the Pokémon for storage at the end of battle
      @caughtPokemon.push(pkmn)
    end
  end

  #=============================================================================
  # Calculate how many shakes a thrown Poké Ball will make (4 = capture)
  #=============================================================================
  def pbCaptureCalc(pkmn,battler,catch_rate,ball)
    return 4 if $DEBUG && Input.press?(Input::CTRL)
    # Get a catch rate if one wasn't provided
    catch_rate = pkmn.species_data.catch_rate if !catch_rate
    # Modify catch_rate depending on the Poké Ball's effect
    ultraBeast = [:NIHILEGO, :BUZZWOLE, :PHEROMOSA, :XURKITREE, :CELESTEELA,
                  :KARTANA, :GUZZLORD, :POIPOLE, :NAGANADEL, :STAKATAKA,
                  :BLACEPHALON].include?(pkmn.species)
    if !ultraBeast || ball == :BEASTBALL
      catch_rate = BallHandlers.modifyCatchRate(ball,catch_rate,self,battler,ultraBeast)
    else
      catch_rate /= 10
    end
    # First half of the shakes calculation
    a = battler.totalhp
    b = battler.hp
    x = ((3*a-2*b)*catch_rate.to_f)/(3*a)
    # Calculation modifiers
    if battler.status == :SLEEP || battler.status == :FROZEN
      x *= 2.5
    elsif battler.status != :NONE
      x *= 1.5
    end
    x = x.floor
    x = 1 if x<1
    # Definite capture, no need to perform randomness checks
    return 4 if x>=255 || BallHandlers.isUnconditional?(ball,self,battler)
    # Second half of the shakes calculation
    y = ( 65536 / ((255.0/x)**0.1875) ).floor
    # Critical capture check
    if Settings::ENABLE_CRITICAL_CAPTURES
      dex_modifier = 0
      numOwned = $Trainer.pokedex.owned_count
      if numOwned>600;    dex_modifier = 5
      elsif numOwned>450; dex_modifier = 4
      elsif numOwned>300; dex_modifier = 3
      elsif numOwned>150; dex_modifier = 2
      elsif numOwned>30;  dex_modifier = 1
      end
      dex_modifier *= 2 if GameData::Item.exists?(:CATCHINGCHARM) && $PokemonBag.pbHasItem?(:CATCHINGCHARM)
      c = x * dex_modifier / 12
      if c>0 && pbRandom(256)<c
        @criticalCapture = true
        return 4 if pbRandom(65536)<y
        return 0
      end
    end
    # Calculate the number of shakes
    numShakes = 0
    for i in 0...4
      break if numShakes<i
      numShakes += 1 if pbRandom(65536)<y
    end
    return numShakes
  end
end
