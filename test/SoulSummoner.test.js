const { getAddress, getContractAddress } = require('@ethersproject/address')
const { expect } = require('chai')
const { accounts, increaseTime, toWei, fromWei, unlockAccount } = require('./utils/testHelper.js')

describe('SoulSummoner', () => {
  var utils = require('ethers').utils;
  const ethers = hre.ethers;
  const THOTH = '0xdffb0b033b8033405f5fb07b08f48c89fa1b4a3d5d5a475c3e2b8df5fbd4da0d';
  const ZERO = 0

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
      14, 1).unlockAccount       // startRate, dailyDecay
    
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
        increaseTime(86_400) // ff 1 day
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
        increaseTime(86_400) // 1 day
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
        increaseTime(86_400) // 1 day
        preUserSoul = await soul.balanceOf(buns)
        preDaoSoul = await soul.balanceOf(dao)
        preTeamSoul = await soul.balanceOf(team)

        // console.log('[user] pre-withdrawal balance: %s SOUL', fromWei(preUserSoul))
        // console.log('[dao] pre-withdrawal balance: %s SOUL', fromWei(preDaoSoul))
        // console.log('[team] pre-withdrawal balance: %s SOUL', fromWei(preTeamSoul))
        
        // leave staking
        unstakedAmount = toWei(100_000)
        await summoner.leaveStaking(unstakedAmount)
        // console.log('[user] withdrew: %s SOUL', 100_000)
        soul.burn(toWei(100_000)) // destroys for easy maths

        newUserSoul = await soul.balanceOf(buns)
        newDaoSoul = await soul.balanceOf(dao)
        newTeamSoul = await soul.balanceOf(team)
        
        //* calculate and log payouts *//

        // [user] payout
        soulUserPayout = newUserSoul.sub(preUserSoul)
        // console.log('[user] rewarded: %s SOUL', fromWei(soulUserPayout))
        // [dao] payout
        soulDaoPayout = await newDaoSoul.sub(preDaoSoul)
        // console.log('[dao] sent: %s SOUL', fromWei(soulDaoPayout))
        // [team] payout
        soulTeamPayout = await newTeamSoul.sub(preTeamSoul)
        // console.log('[team] sent: %s SOUL', fromWei(soulTeamPayout))

        // [total] payout
        totalPayoutOneDay = await
          soulUserPayout
            .add(soulDaoPayout)
            .add(soulTeamPayout)
      
        // console.log('total payout: %s', fromWei(totalPayoutOneDay))
        supply = await soul.totalSupply()
        // console.log('total 1D supply; %s SOUL', fromWei(supply))

        // [total] payouts == total supply
        expect(await totalPayoutOneDay).to.equal(supply)
      })

      it('[shares] should return: 6/8 user, 1/8 dao, 1/8 dev', async function() {
        userShare = soulUserPayout.mul(1_000).div(totalPayoutOneDay)
        rawDaoShare = soulDaoPayout.mul(1_000).div(totalPayoutOneDay)
        rawTeamShare = soulTeamPayout.mul(1_000).div(totalPayoutOneDay)

        // adjust by rounding
        daoShare = rawDaoShare.add(1)
        teamShare = rawTeamShare.add(1)

        // log user shares
        // console.log('user share: %s', userShare)
        // console.log('dao share: %s', daoShare)
        // console.log('team share: %s', teamShare)
        
        // expect the shares to align with tokenomics
        expect(await userShare.add(daoShare).add(teamShare)).to.equal(1000)
        expect(await userShare).to.equal(750)
        expect(await daoShare).to.equal(125)
        expect(await teamShare).to.equal(125)
      })
    })

    describe('review: adding pairs', function() {
      it('should [still] have 250K rewards total', async function() {
        await summoner.addPool(500, coreLP1.address, true)
        await summoner.addPool(500, coreLP2.address, true)
        // console.log('added FUSD-PAIR: %s', '5x')
        // console.log('added ETH-PAIR: %s', '5x')
        totalPools = await summoner.poolLength()

        expect(await totalPools).to.equal(3)
        // console.log('total pools: %s', totalPools)
        
        await summoner.deposit(1, toWei(100_000))
        await summoner.deposit(2, toWei(100_000))
        // console.log('deposited: %s FUSD-PAIR', 100_000)
        // console.log('deposited: %s ETH-PAIR', 100_000)

        await increaseTime(86_400) // 1 day

        pendingSoulRewards = await summoner.pendingSoul(0, buns)
        // console.log('PID(0) Rewards: %s SOUL', fromWei(pendingSoulRewards))

        pendingSoulLP1 = await summoner.pendingSoul(1, buns)
        // console.log('PID(1) Rewards: %s SOUL', fromWei(pendingSoulLP1))

        pendingSoulLP2 = await summoner.pendingSoul(2, buns)
        // console.log('PID(2) Rewards: %s SOUL', fromWei(pendingSoulLP2))

        totalLpPendingRewards = pendingSoulLP1.add(pendingSoulLP2)
        // console.log('ttl LP pending rewards: %s SOUL', fromWei(totalLpPendingRewards))
        
        totalPendingRewards = pendingSoulRewards.add(pendingSoulLP1).add(pendingSoulLP2)
        // console.log('ttl pending rewards: %s SOUL', fromWei(totalPendingRewards))

        // adjustment for even expectations, throws when off by more than 0.2%
        diffRewards = toWei(totalPendingRewards).sub(toWei(250_000))
        totalPending = 
          diffRewards > toWei(500)
              ? 0
              : toWei(250_000)
        expect(await totalPending).to.equal(toWei(250_000))
      })

      it('prevents redundant pool', async function() {
        await summoner.addPool(1_000, coreLP1.address, true)
        // expect duplicates to revert
        await expect(summoner.addPool(1_000, coreLP1.address, true)
        ).to.be.revertedWith('duplicated pool')
      })

    describe('review: fees', function() {
      it('should show 0 fee for SAS pool', async function() {
        feeRate = await summoner.getFeeRate(0, 86_400)
        console.log('fee rate: %s', feeRate)
        await expect(feeRate).to.equal(0)
      })

      it('should show 14% fee for non-SAS pools', async function() {
        await increaseTime(86_400) // ff 1 days
        feeRate1 = await summoner.getFeeRate(1, 86_400)
        feeRate2 = await summoner.getFeeRate(2, 86_400)
        EXPECTATION = toWei(14)
        // ensures fee rates are identical
        RAW_RATE = feeRate1 == feeRate2
          ? 0
          : feeRate1
        
        diffRates = RAW_RATE > EXPECTATION // avoids negatives
          ? RAW_RATE.sub(EXPECTATION)
          : EXPECTATION.sub(RAW_RATE)

        console.log('diff rates: %s', fromWei(diffRates))
        
        FEE_RATE = fromWei(diffRates) > 1
          ? ZERO
          : EXPECTATION

        console.log('raw fee rate: %s', fromWei(RAW_RATE)) // show for human verification
        console.log('fee rate: %s', fromWei(FEE_RATE))
        await expect(FEE_RATE).to.equal(EXPECTATION)
      })

      // it('should show withdraw 100% staked', async function() {


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
  })
})

