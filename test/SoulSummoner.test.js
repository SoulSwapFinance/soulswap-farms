const { getAddress, getContractAddress } = require('@ethersproject/address')
const { expect } = require('chai')
const { accounts, increaseTime, toWei, fromWei, unlockAccount } = require('./utils/testHelper.js')

describe('SoulSummoner', () => {
  var utils = require('ethers').utils;
  const ethers = hre.ethers;
  const THOTH = '0xdffb0b033b8033405f5fb07b08f48c89fa1b4a3d5d5a475c3e2b8df5fbd4da0d';

  beforeEach(async () => {
    
    // fetch and store contracts 
    SoulPower = await ethers.getContractFactory('MockSoulPower')
    SeanceCircle = await ethers.getContractFactory('MockSeanceCircle')
    Summoner = await ethers.getContractFactory('MockSoulSummoner')
    LPToken = await ethers.getContractFactory('MockToken')
    
    provider =  await ethers.provider;
    signer = await provider.getSigner()
  
    // deploy contracts
    soul = await SoulPower.deploy()
    await soul.deployed()
    
    seance = await SeanceCircle.deploy()
    await seance.deployed()
    
    summoner = await Summoner.deploy()
    await summoner.deployed()
    
    lpToken = await LPToken.deploy()
    await lpToken.deployed()
        
    // initialize and grant roles
    await soul.grantRole(THOTH, summoner.address)
    console.log('%s role granted', "THOTH")
    
    await seance.addOperator(summoner.address)
    console.log('operator added')

    await seance.initialize(soul.address)    
    console.log('initialized: seance')
    
    await summoner.initialize(
      soul.address,    // soul
      seance.address, // seance
      0, 1000,       // total weight, weight
      1000,         // staking allocation
      14, 1).unlockAccount       // startRate, dailyDecay
    
    console.log('initialized: summoner')
    
    buns = await signer.getAddress()
    console.log('my address: %s', buns)

    // approve, and mint lp and burn excess soul
    await soul.approve(summoner.address, toWei(10000))
    await lpToken.approve(summoner.address, toWei(10000))
    lpToken.mint(toWei(10000))
    console.log('minted %s tokens', 10000)
    soul.burn(toWei(49990000))
    console.log('burned excess tokens')

    team = '0x81Dd37687c74Df8F957a370A9A4435D873F5e5A9'
    dao = '0x1C63C726926197BD3CB75d86bCFB1DaeBcD87250'

    // update accounts to dao and team (multi-sigs)
    await summoner.updateAccounts(dao, team)
    console.log('dao: %s', dao)
    console.log('team: %s', team)
    
    // [user] enter staking
    await summoner.enterStaking(toWei(10000))
    soulUserStaked = await soul.balanceOf(summoner.address)
    console.log('[user] staked %s SOUL', fromWei(soulUserStaked))
  })

    // deposit test
    describe('deposits / withdraws', function() {
        it('should return 10,000 SOUL in the summoner', async function() {
          console.log('summoner soul bal', fromWei(soulUserStaked))
          expect(await soul.balanceOf(summoner.address)).to.equal(toWei(10000))
        })
    })

    // staking rewards pending verification
    describe('view rewards days one and two', function() {
        it('should return rewards balances of ~250K and ~500K', async function() {
        increaseTime(86400) // ff 1 day
        dayOneRewards = await summoner.pendingSoul(0, buns)
        console.log('D1 Rewards %s: ', fromWei(dayOneRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(dayOneRewards)
        
        await increaseTime(86400) // ff 2 days
        dayTwoRewards = await summoner.pendingSoul(0, buns)
        console.log('D2 Rewards %s: ', fromWei(dayTwoRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(dayTwoRewards)

      })
    })

    // withdraw and allocate
    describe('withdraw staked soul', function() {
      it('should return soul balance + rewards balance', async function() {
        increaseTime(86400) // 1 day
        pendingRewards = await summoner.pendingSoul(0, buns)
        console.log('pending soul %s: ', fromWei(pendingRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(pendingRewards)
        
        dao = await summoner.dao()
        team = await summoner.team()

        summonerSoulBalance = await soul.balanceOf(summoner.address)
        console.log('[summoner] balance: %s SOUL', fromWei(summonerSoulBalance))
        expect(await soul.balanceOf(summoner.address)).to.equal(summonerSoulBalance)
        
        preUserSoul = await soul.balanceOf(buns)
        preDaoSoul = await soul.balanceOf(dao)
        preTeamSoul = await soul.balanceOf(team)

        console.log('[user] pre-withdrawal balance: %s SOUL', fromWei(preUserSoul))
        console.log('[dao] pre-withdrawal balance: %s SOUL', fromWei(preDaoSoul))
        console.log('[team] pre-withdrawal balance: %s SOUL', fromWei(preTeamSoul))
        
        // leave staking
        await summoner.leaveStaking(toWei(10000))
        console.log('left staking')

        newUserSoul = await soul.balanceOf(buns)
        newDaoSoul = await soul.balanceOf(dao)
        newTeamSoul = await soul.balanceOf(team)
        
        // calculate and log payouts //

        // [user] payout
        soulUserPayout = await newUserSoul.sub(preUserSoul)
        await soulUserPayout
        console.log('user paid out: %s SOUL', fromWei(soulUserPayout))
        
        // [dao] payout
        soulDaoPayout = await newDaoSoul.sub(preDaoSoul)
        await soulDaoPayout
        console.log('user paid out: %s SOUL', fromWei(soulDaoPayout))
        
        // [team] payout
        soulTeamPayout = await newTeamSoul.sub(preTeamSoul)
        await soulTeamPayout
        console.log('user paid out: %s SOUL', fromWei(soulTeamPayout))

        totalPayoutOneDay = await
          soulUserPayout
            .add(soulDaoPayout)
            .add(soulTeamPayout)
      
        console.log('total payout: %s', fromWei(totalPayoutOneDay))
        supply = await soul.totalSupply()
        console.log('supply; %s SOUL', fromWei(supply))
      })
    })
})

