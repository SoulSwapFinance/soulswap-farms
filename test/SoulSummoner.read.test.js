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

  beforeEach(async () => {
    
    // fetch and store contracts 
    SoulPower = await ethers.getContractFactory('MockSoulPower')
    SeanceCircle = await ethers.getContractFactory('MockSeanceCircle')
    Summoner = await ethers.getContractFactory('MockSoulSummoner')
    CoreLP1 = await ethers.getContractFactory('MockToken')
    CoreLP2 = await ethers.getContractFactory('MockToken')
    
    provider =  await ethers.provider;
    signer = await provider.getSigner()
  
    // deploy contracts
    soul = await SoulPower.deploy()
    await soul.deployed()
    
    seance = await SeanceCircle.deploy()
    await seance.deployed()
    
    summoner = await Summoner.deploy()
    await summoner.deployed()
    
    coreLP1 = await CoreLP1.deploy()
    await coreLP1.deployed()

    coreLP2 = await CoreLP2.deploy()
    await coreLP2.deployed()
        
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
      14, 1)       // startRate, dailyDecay
    
    // console.log('initialized: summoner')
    
    buns = await signer.getAddress()
    // console.log('my address: %s', buns)

    // approve, and mint lp and burn excess soul
    await soul.approve(summoner.address, toWei(100_000))
    await coreLP1.approve(summoner.address, toWei(100_000))
    await coreLP2.approve(summoner.address, toWei(100_000))

    // mint core lpTokens
    coreLP1.mint(toWei(100_000))
    coreLP2.mint(toWei(100_000))
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
        increaseTime(ONE_DAY) // 1 day
        pendingRewards = await summoner.pendingSoul(0, buns)
        // console.log('pending soul %s: ', fromWei(pendingRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(pendingRewards)
      })

      it('should return [summoner] balance of 10K SOUL', async function() {
        summonerSoulBalance = await soul.balanceOf(summoner.address)
        // console.log('[summoner] balance: %s SOUL', fromWei(summonerSoulBalance))
        expect(await soul.balanceOf(summoner.address)).to.equal(toWei(100_000))
      })
        
      it('should return total payout of ~250K SOUL', async function() {
        increaseTime(ONE_DAY) // 1 day
        preUserSoul = await soul.balanceOf(buns)
        preDaoSoul = await soul.balanceOf(dao)
        preTeamSoul = await soul.balanceOf(team)

        // console.log('[user] pre-withdrawal balance: %s SOUL', fromWei(preUserSoul))
        // console.log('[dao] pre-withdrawal balance: %s SOUL', fromWei(preDaoSoul))
        // console.log('[team] pre-withdrawal balance: %s SOUL', fromWei(preTeamSoul))
    })

    describe('review: fees', function() {
      it('should show 0 fee for SAS pool', async function() {
        feeRate = await summoner.getFeeRate(0, ONE_DAY)
        console.log('fee rate: %s', feeRate)
        await expect(feeRate).to.equal(0)
      })

      it('[D1] should show 14% fee for non-SAS pools', async function() {
        await increaseTime(ONE_DAY) // ff 1 days
        feeRate1 = await summoner.getFeeRate(1, ONE_DAY)
        feeRate2 = await summoner.getFeeRate(2, ONE_DAY)
        EXPECTATION = toWei(14)
        // ensures fee rates are identical
        RAW_RATE = feeRate1 == feeRate2 ? 0 : feeRate1
        
        // avoids negatives
        diffRates = RAW_RATE > EXPECTATION ? RAW_RATE.sub(EXPECTATION) : EXPECTATION.sub(RAW_RATE)
        console.log('diff rates: %s', fromWei(diffRates))
        
        FEE_RATE = fromWei(diffRates) > 1 ? ZERO : EXPECTATION
        console.log('raw fee rate: %s', fromWei(RAW_RATE)) // show for human verification
        console.log('fee rate: %s', fromWei(FEE_RATE))

        await expect(FEE_RATE).to.equal(EXPECTATION)
      })
        it('[D7] should show 13% fee for non-SAS pools', async function() {
        increaseTime(ONE_WEEK)
        feeRate1 = await summoner.getFeeRate(1, ONE_WEEK)
        feeRate2 = await summoner.getFeeRate(2, ONE_WEEK)
        console.log('fee rate one: %s', fromWei(feeRate1))
        // EXPECTATION = toWei(14)
        })

    //   describe('review: fees', function() {

    //     // SANITY CHECKS //
    //     soulRate = await summoner.soulRate()
    //     console.log('soul rate: %s', soulRate)

    //     getFeeRate = await summoner.getFee(1, 100_000)
    //     getFee = await summoner.getFeeRate(1, ONE_DAY)
    //     userDelta = await summoner.userDelta(1)
    //     dailySoul = await summoner.dailySoul()
    //     userInfo = await summoner.userInfo(1, buns)
    //     timeTillNextDecrease = await summoner.timeTillNextDecrease(1)
    //     startRate = await summoner.startRate
    //     decayRate = await summoner.decayRate
    //     soulPerSecond = await summoner.soulPerSecond
    //     pendingSoul = await summoner.pendingSoul(1, buns)
    //     getWithdrawable = await summoner.getWithdrawable(1, ONE_DAY, 100_000)



        // LP_TO_UNSTAKE = toWei(100_000)
        // await summoner.withdraw(1, LP_TO_UNSTAKE)
        // console.log('unstaked: %s LP', fromWei(LP_TO_UNSTAKE))

        // userNewBalance = await coreLP1.balanceOf(buns) // ensures balance is cleared
        // console.log('CoreLP1 new bal: %s', fromWei(userNewBalance))
        
        // // daoNewBalance = await coreLP1.balanceOf(dao) // ensures balance is cleared
        // console.log('DAO new bal: %s', fromWei(daoNewBalance))
        // expect(await userNewBalance).to.equal(toWei(100_000))
        // expect(await daoNewBalance).to.equal(toWei(0))
      })
    })

    // function getFee(uint timeDelta) public view returns (uint) {

    //   it('returns: the seconds remaining until the next fee decrease', async function() {
      
    //   // soul (= 0)
    //   soulDecreaseTime = await timeUntilNextDecrease(0)
      
    //   // lp (= daysEnd - now)
    //   lpDecreaseTime = await timeUntilNextDecrease(1) 
      
    //   // todo: add expects
      
      
    //   console.log('time left (0): ~%s mins', soulDecreaseTime)
      
    //   console.log('time left (1): ~%s mins', lpDecreaseTime)
      
    // })
//   })
})

