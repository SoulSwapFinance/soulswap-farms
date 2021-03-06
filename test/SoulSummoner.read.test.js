const { getAddress, getContractAddress } = require('@ethersproject/address')
const { expect } = require('chai')
const { accounts, increaseTime, toWei, fromWei, unlockAccount } = require('./utils/testHelper.js')

describe('SoulSummoner', () => {
  // var utils = require('ethers').utils
  const ethers = hre.ethers
  const THOTH = '0xdffb0b033b8033405f5fb07b08f48c89fa1b4a3d5d5a475c3e2b8df5fbd4da0d'
  const ZERO = 0
  const ONE_DAY = 86_400
  const ONE_WEEK = 604_800
  const TWO_WEEKS = 1_209_600
  const HUNDRED_THOUSAND = 100_000

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
    // console.log('%s role granted', "THOTH")
    
    await seance.addOperator(summoner.address)
    // console.log('operator added')

    await seance.initialize(soul.address)    
    // console.log('initialized: seance')
    
    await summoner.initialize(
      soul.address,    // soul
      seance.address, // seance
      0, 1000,       // total weight, weight
      1000,         // staking allocation
      14)          // startRate
    
    // console.log('initialized: summoner')
    
    buns = await signer.getAddress()
    // console.log('my address: %s', buns)

    // approve, and mint lp and burn excess soul
    await soul.approve(summoner.address, toWei(HUNDRED_THOUSAND))
    await lpToken.approve(summoner.address, toWei(HUNDRED_THOUSAND))

    // mint core lpTokens
    lpToken.mint(toWei(HUNDRED_THOUSAND))
    // console.log('minted %s tokens for ea. core pool', 100_000)

    // burn excess SOUL
    soul.burn(toWei(49_900_000))
    // console.log('burned excess tokens')

    team = '0x81Dd37687c74Df8F957a370A9A4435D873F5e5A9'
    dao = '0x1C63C726926197BD3CB75d86bCFB1DaeBcD87250'

    // update accounts to dao and team (multi-sigs)
    await summoner.updateAccounts(dao, team)
    // console.log('dao: %s', dao)
    // console.log('team: %s', team)
    
    // [user] enter staking
    await summoner.enterStaking(toWei(100_000))
    soulUserStaked = await soul.balanceOf(summoner.address)
    // console.log('[user] staked %s SOUL', fromWei(soulUserStaked))
  })

    // deposit test
    describe('review: balances and rewards', function() {

      it('should return 10,000 SOUL in the summoner', async function() {
          // console.log('summoner soul bal', fromWei(soulUserStaked))
          expect(await soul.balanceOf(summoner.address)).to.equal(toWei(100_000))
        })

      it('should return [D1] rewards balances of ~250K', async function() {
        increaseTime(ONE_DAY) // ff 1 day
        dayOneRewards = await summoner.pendingSoul(0, buns)
        // console.log('D1 Rewards %s: ', fromWei(dayOneRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(dayOneRewards)
        })

      it('should return [D2] rewards balances of ~500K', async function() {
        await increaseTime(172_800) // ff 2 days
        dayTwoRewards = await summoner.pendingSoul(0, buns)
        // console.log('D2 Rewards %s: ', fromWei(dayTwoRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(dayTwoRewards)
        })
    })

    // withdraw and allocate
    describe('review: withdrawing staked soul', function() {

      it('should return pending rewards of ~250K', async function() {
        await increaseTime(ONE_DAY) // 1 day
        pendingRewards = await summoner.pendingSoul(0, buns)
        console.log('pending soul %s: ', fromWei(pendingRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(pendingRewards)
      })

      it('should return [summoner] balance of 10K SOUL', async function() {
        summonerSoulBalance = await soul.balanceOf(summoner.address)
        // console.log('[summoner] balance: %s SOUL', fromWei(summonerSoulBalance))
        expect(await soul.balanceOf(summoner.address)).to.equal(toWei(100_000))
      })
    })

    describe('review: fee rates', function() {

      it('[D1] expects LP: 13%', async function() {
        let SAS_EXPECTATION = 0
        let LP_EXPECTATION = toWei(13)
        
        let SAS_RATE = await summoner.getFeeRate(0, ONE_DAY)
        let LP_RATE = await summoner.getFeeRate(1, ONE_DAY)

        console.log('[D1 | SAS] fee: %s%', fromWei(SAS_RATE))
        console.log('[D1 | LP] fee: %s%', fromWei(LP_RATE))

        await expect(SAS_RATE).to.equal(SAS_EXPECTATION)
        await expect(LP_RATE).to.equal(LP_EXPECTATION)
      })

      it('[D7] expects LP: 7%', async function() {
        let SAS_EXPECTATION = 0
        let LP_EXPECTATION = toWei(7)
        
        let SAS_RATE = await summoner.getFeeRate(0, ONE_WEEK)
        let LP_RATE = await summoner.getFeeRate(1, ONE_WEEK)

        console.log('[D7 | SAS] fee: %s%', fromWei(SAS_RATE))
        console.log('[D7 | LP] fee: %s%', fromWei(LP_RATE))

        await expect(SAS_RATE).to.equal(SAS_EXPECTATION)
        await expect(LP_RATE).to.equal(LP_EXPECTATION)
      })

      it('[D14] expects SAS & LP: 0% fee', async function() {
        let SAS_EXPECTATION = 0
        let LP_EXPECTATION = 0
        
        let SAS_RATE = await summoner.getFeeRate(0, TWO_WEEKS)
        let LP_RATE = await summoner.getFeeRate(1, TWO_WEEKS)

        console.log('[D14 | SAS] fee: %s%', fromWei(SAS_RATE))
        console.log('[D14 | LP] fee: %s%', fromWei(LP_RATE))

        await expect(SAS_RATE).to.equal(SAS_EXPECTATION)
        await expect(LP_RATE).to.equal(LP_EXPECTATION)
      })
    })

  describe('review: emissions', function() {
    it('expects dailySoul: 250K', async function() {
      let EXPECTATION = toWei(250_000)
      let DAILY_SOUL = await summoner.dailySoul()
      
      console.log('daily soul: %s', fromWei(DAILY_SOUL))
      await expect(DAILY_SOUL).to.equal(EXPECTATION)
    })

    it('[expects (halved) dailySoul: 125K', async function() {
      await summoner.updateWeights(500, 1000)

      let EXPECTATION = await toWei(125_000)
      let DAILY_SOUL = await summoner.dailySoul()

      console.log('daily soul: %s', fromWei(DAILY_SOUL))
      await expect(DAILY_SOUL).to.equal(EXPECTATION)
    })

    it('expects (halved) soulPerSecond: soulPerSecond / 2', async function() {
      let PRE_RATE = await summoner.soulPerSecond()
      console.log('soul per second: %s', fromWei(PRE_RATE))

      await summoner.updateWeights(500, 1000)

      let EXPECTATION = await PRE_RATE.div(2)
      let DAILY_SOUL = await summoner.dailySoul()
      let SOUL_PER_SEC = await summoner.soulPerSecond()
      console.log('daily soul: %s', fromWei(DAILY_SOUL))
      console.log('soul per second: %s', fromWei(SOUL_PER_SEC))
      
      await expect(SOUL_PER_SEC).to.equal(EXPECTATION)
    })
  })

  describe('review: rewards', function() {
    it('expects pendingSoul: ~250K', async function() {
      let DAILY_SOUL = await summoner.dailySoul()
      console.log('daily SOUL: %s SOUL', fromWei(DAILY_SOUL))

      await increaseTime(ONE_DAY)
      let PENDING_SOUL = await summoner.pendingSoul(0, buns)
      console.log('pending SOUL: %s', fromWei(PENDING_SOUL))
    })
  })

  describe('review: user delta', function() {
    it('expects userDelta[1]: ~250K', async function() {
      await soul.approve(summoner.address, HUNDRED_THOUSAND)
      await soul.mint(buns, HUNDRED_THOUSAND)
      await summoner.enterStaking(HUNDRED_THOUSAND)
      soulUserStaked = await soul.balanceOf(summoner.address)
      console.log('staked')

      await summoner.leaveStaking(100_000)
      let USER_DELTA = await summoner.userDelta(0, buns)
      console.log('user delta: %s', USER_DELTA)

      await increaseTime(ONE_DAY)
      let USER_DELTA_ONE_DAY = await summoner.userDelta(0, buns)
      console.log('day one delta: %s', USER_DELTA_ONE_DAY)
      console.log('diff: %s', USER_DELTA_ONE_DAY.sub(USER_DELTA))
      
      await increaseTime(ONE_DAY)
      let USER_DELTA_TWO_DAY = await summoner.userDelta(0, buns)
      console.log('day 2 delta: %s', USER_DELTA_TWO_DAY)
      console.log('diff: %s', USER_DELTA_TWO_DAY.sub(USER_DELTA_ONE_DAY))

      // let PENDING_SOUL = await summoner.pendingSoul(0, buns)
      // console.log('pending SOUL: %s', fromWei(PENDING_SOUL))
    })
  })
})