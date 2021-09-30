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
      14)       // startRate
      
      // console.log('initialized: summoner')
      
      buns = await signer.getAddress()
      // console.log('my address: %s', buns)
      
    // approve, and mint lp and burn excess soul
    await soul.approve(summoner.address, toWei(HUNDRED_THOUSAND))
    await lpToken.approve(summoner.address, toWei(HUNDRED_THOUSAND))
    
    // mint core lpTokens
    lpToken.mint(toWei(HUNDRED_THOUSAND))
    // console.log('minted %s tokens for ea. core pool', HUNDRED_THOUSAND)
    
    // burn excess SOUL [removed]
    // soul.burn(toWei(49_900_000))
    // console.log('burned excess tokens')
    console.log('total supply of SOUL: %s', await soul.totalSupply())

    team = '0x81Dd37687c74Df8F957a370A9A4435D873F5e5A9'
    dao = '0x1C63C726926197BD3CB75d86bCFB1DaeBcD87250'

    // update accounts to dao and team (multi-sigs)
    await summoner.updateAccounts(dao, team)
    // console.log('dao: %s', dao)
    // console.log('team: %s', team)
    
    
    // [user] enter staking
    await summoner.enterStaking(toWei(HUNDRED_THOUSAND))
    soulUserStaked = await soul.balanceOf(summoner.address)
    // console.log('[user] staked %s SOUL', fromWei(soulUserStaked))
  })

    // deposit test
    describe('review: balances and rewards', function() {
        it('should return 100,000 SOUL in the summoner', async function() {
          console.log('summoner soul bal', fromWei(soulUserStaked))
          expect(await soul.balanceOf(summoner.address)).to.equal(toWei(HUNDRED_THOUSAND))
        })

        it('should return [D1] rewards balances of ~250K', async function() {
        increaseTime(ONE_DAY) // ff 1 day
        dayOneRewards = await summoner.pendingSoul(0, buns) // [   XXX   ]
        console.log('D1 Rewards %s: ', fromWei(dayOneRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(dayOneRewards)
        })

        it('should return [D2] rewards balances of ~500K', async function() {
        await increaseTime(172_800) // ff 2 days
        dayTwoRewards = await summoner.pendingSoul(0, buns)
        console.log('D2 Rewards %s: ', fromWei(dayTwoRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(dayTwoRewards)
        })
    })

    // withdraw and allocate
    describe('review: withdrawing staked soul', function() {
      it('should return pending rewards of ~250K', async function() {
        increaseTime(ONE_DAY) // 1 day
        pendingRewards = await summoner.pendingSoul(0, buns)
        console.log('pending soul %s: ', fromWei(pendingRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(pendingRewards)
      })

      it('should return [summoner] balance of 100K SOUL', async function() {
        summonerSoulBalance = await soul.balanceOf(summoner.address)
        console.log('[summoner] balance: %s SOUL', fromWei(summonerSoulBalance))
        expect(await soul.balanceOf(summoner.address)).to.equal(toWei(HUNDRED_THOUSAND))
      })
        
      it('should return total payout of ~250K SOUL', async function() {
        increaseTime(ONE_DAY) // 1 day
        preUserSoul = await soul.balanceOf(buns)
        preDaoSoul = await soul.balanceOf(dao)
        preTeamSoul = await soul.balanceOf(team)

        console.log('[user] pre-withdrawal balance: %s SOUL', fromWei(preUserSoul))
        console.log('[dao] pre-withdrawal balance: %s SOUL', fromWei(preDaoSoul))
        console.log('[team] pre-withdrawal balance: %s SOUL', fromWei(preTeamSoul))
        
        // leave staking
        unstakedAmount = toWei(HUNDRED_THOUSAND)
        await summoner.leaveStaking(unstakedAmount)
        console.log('[user] withdrew: %s SOUL', HUNDRED_THOUSAND)
        soul.burn(toWei(HUNDRED_THOUSAND)) // destroys for easy maths

        newUserSoul = await soul.balanceOf(buns)
        newDaoSoul = await soul.balanceOf(dao)
        newTeamSoul = await soul.balanceOf(team)
        
        //* calculate and log payouts *//

        // [user] payout
        soulUserPayout = newUserSoul.sub(preUserSoul)
        console.log('[user] rewarded: %s SOUL', fromWei(soulUserPayout))

        // [dao] payout
        soulDaoPayout = await newDaoSoul.sub(preDaoSoul)
        console.log('[dao] sent: %s SOUL', fromWei(soulDaoPayout))

        // [team] payout
        soulTeamPayout = await newTeamSoul.sub(preTeamSoul)
        console.log('[team] sent: %s SOUL', fromWei(soulTeamPayout))

        // [total] payout
        totalPayoutOneDay = await
          soulUserPayout
            .add(soulDaoPayout)
            .add(soulTeamPayout)
      
        console.log('total payout: %s', fromWei(totalPayoutOneDay))
        
        supply = await soul.totalSupply()
        console.log('total 1D supply; %s SOUL', fromWei(supply)) // [ XXX ]

        // [  XXX  ]
        summonerSoulBalance = await soul.balanceOf(summoner.address)
        seanceSoulBalance = await soul.balanceOf(seance.address)
        console.log('[summoner] balance: %s SOUL', summonerSoulBalance)
        console.log('[seance] balance: %s SOUL', seanceSoulBalance) // [ XXX ]

        // [total] payouts == total supply
        expect(await totalPayoutOneDay).to.equal(supply)
        // 250_002.893518518518473718 501_500_028.93518518518473718

        increaseTime(ONE_DAY) // 1 day

        // harvest staking rewards on D2 [  XXX  ]
        await summoner.leaveStaking(ZERO)
        summonerSoulBalanceDay2 = soul.balanceOf(summoner.address)
        seanceSoulBalanceDay2 = soul.balanceOf(seance.address)
        console.log('[D2] Seance Balance: % SOUL', seanceSoulBalanceDay2)
        console.log('[D2] Summoner Balance: % SOUL', summonerSoulBalanceDay2)

        console.log('harvested soul')


      })

      it('[shares] should return: 6/8 user, 1/8 dao, 1/8 dev', async function() {
        userShare = soulUserPayout.mul(1_000).div(totalPayoutOneDay)
        rawDaoShare = soulDaoPayout.mul(1_000).div(totalPayoutOneDay)
        rawTeamShare = soulTeamPayout.mul(1_000).div(totalPayoutOneDay)
        // adjust by rounding
        daoShare = rawDaoShare.add(1)
        teamShare = rawTeamShare.add(1)

        // log user shares
        console.log('user share: %s', userShare)
        console.log('dao share: %s', daoShare)
        console.log('team share: %s', teamShare)
        
        // expect the shares to align with tokenomics
        expect(await userShare.add(daoShare).add(teamShare)).to.equal(1000)
        expect(await userShare).to.equal(750)
        expect(await daoShare).to.equal(125)
        expect(await teamShare).to.equal(125)
      })
    })

    describe('review: adding pairs', function() {
      it('should [still] have 250K rewards total', async function() {
        await summoner.addPool(500, lpToken.address, true)
        // console.log('added FUSD-PAIR: %s', '5x')
        // console.log('added ETH-PAIR: %s', '5x')
        totalPools = await summoner.poolLength()

        expect(await totalPools).to.equal(2)
        // console.log('total pools: %s', totalPools)
        
        await summoner.deposit(1, toWei(HUNDRED_THOUSAND))
        // console.log('deposited: %s FUSD-PAIR', HUNDRED_THOUSAND)
        // console.log('deposited: %s ETH-PAIR', HUNDRED_THOUSAND)

        await increaseTime(ONE_DAY) // 1 day

        pendingSoulRewards = await summoner.pendingSoul(0, buns)
        // console.log('PID(0) Rewards: %s SOUL', fromWei(pendingSoulRewards))

        pendingSoulLP = await summoner.pendingSoul(1, buns)
        // console.log('LP Rewards: %s SOUL', fromWei(pendingSoulLP))
        
        totalPendingRewards = pendingSoulRewards.add(pendingSoulLP)
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
        await summoner.addPool(1_000, lpToken.address, true)
        // expect duplicates to revert
        await expect(summoner.addPool(1_000, lpToken.address, true)
        ).to.be.revertedWith('duplicated pool')
      })

    describe('review: fees', function() {

      it('should show 0 fee for SAS pool', async function() {
        feeRate = await summoner.getFeeRate(0, ONE_DAY)
        console.log('[SAS] fee rate: %s', fromWei(feeRate))
        await expect(feeRate).to.equal(0)
      })

      it('[D1] should show 13% fee for non-SAS pools', async function() {
        await increaseTime(ONE_DAY) // ff 1 days
        feeRate1 = await summoner.getFeeRate(1, ONE_DAY)
        feeRate2 = await summoner.getFeeRate(2, ONE_DAY)
        FEE_RATE = feeRate1 == feeRate2 ? 0 : feeRate1
        EXPECTATION = toWei(13)
        await expect(FEE_RATE).to.equal(EXPECTATION)
      })
    })
    
    describe('review: withdrawals', function() {
      it('should withdraw 100% staked', async function() {
        await increaseTime(ONE_DAY) // ff 1 days
        preWithdrawalBalance = await soul.balanceOf(buns)
        console.log('soul bal: %s', fromWei(preWithdrawalBalance))

        SOUL_TO_UNSTAKE = toWei(HUNDRED_THOUSAND)
        rawPendingRewards = await summoner.pendingSoul(0, buns)
        PENDING_REWARDS = rawPendingRewards.mul(3e12).div(4e12) // 75% of share to miners
        console.log('user pending rewards: %s', fromWei(PENDING_REWARDS))
  
        await summoner.leaveStaking(SOUL_TO_UNSTAKE)
        
        console.log('withdrew %s SOUL', fromWei(SOUL_TO_UNSTAKE))
        userBalance = await soul.balanceOf(buns)
        console.log('new bal: %s SOUL', fromWei(userBalance))
        
        RAW_SOUL_UNSTAKED = userBalance.sub(PENDING_REWARDS) // removes pending rewards from calc
        console.log('unstaked: %s SOUL', fromWei(RAW_SOUL_UNSTAKED))
        
        EXPECTATION = toWei(HUNDRED_THOUSAND)
        diffRates = RAW_SOUL_UNSTAKED > EXPECTATION // avoids negatives
        ? RAW_SOUL_UNSTAKED.sub(EXPECTATION)
        : EXPECTATION.sub(RAW_SOUL_UNSTAKED)
        console.log('diff rates: %s', fromWei(diffRates))
        
        SOUL_UNSTAKED = fromWei(diffRates) > 5 // allows deviation of 5/100,000 = 0.005%
          ? ZERO
          : EXPECTATION

        await expect(SOUL_UNSTAKED).to.equal(SOUL_TO_UNSTAKE)
      })

      it('should withdraw 87% LP staked on D1', async function() {
        await summoner.addPool(500, lpToken.address, true)
        // console.log('added FTM-PAIR: %s', '5x')
        totalPools = await summoner.poolLength()

        expect(await totalPools).to.equal(2)
        // console.log('total pools: %s', totalPools)
        
        await summoner.deposit(1, toWei(HUNDRED_THOUSAND))
        console.log('deposited: %s FTM-PAIR', HUNDRED_THOUSAND)
        
        await increaseTime(ONE_DAY) // ff 1 days
        await lpToken.burn(toWei(HUNDRED_THOUSAND)) // clears out LP balance from buns
        preWithdrawalBalance = await lpToken.balanceOf(buns) // ensures balance is cleared
        console.log('[buns] pre-bal: %s', fromWei(preWithdrawalBalance))

        LP_TO_UNSTAKE = toWei(HUNDRED_THOUSAND)
        await summoner.withdraw(1, LP_TO_UNSTAKE)
        console.log('[buns] unstaked: %s LP', fromWei(LP_TO_UNSTAKE))

        userNewBalance = await lpToken.balanceOf(buns) // ensures balance is cleared
        console.log('[buns] LP new bal: %s', fromWei(userNewBalance))
        
        daoNewBalance = await lpToken.balanceOf(dao) // ensures balance is cleared
        console.log('[dao] LP new bal: %s', fromWei(daoNewBalance))
        expect(await userNewBalance).to.equal(toWei(87_000))
        expect(await daoNewBalance).to.equal(toWei(13_000))
      })

      it('[1W] should withdraw 93K LP', async function() {

        await summoner.addPool(500, lpToken.address, true)
        // console.log('added FTM-PAIR: %s', '5x')
        totalPools = await summoner.poolLength()

        expect(await totalPools).to.equal(2)
        // console.log('total pools: %s', totalPools)
        
        await summoner.deposit(1, toWei(HUNDRED_THOUSAND))
        console.log('[buns] deposited: %s FTM-PAIR', HUNDRED_THOUSAND)

        await increaseTime(ONE_WEEK) // ff 7 days
        await lpToken.burn(toWei(HUNDRED_THOUSAND)) // clears out LP balance from buns
        
        PRE_BALANCE = await lpToken.balanceOf(buns) // ensures balance is cleared
        console.log('[buns] LP pre-bal: %s', fromWei(PRE_BALANCE))
        
        await summoner.withdraw(1, toWei(HUNDRED_THOUSAND))
        POST_BALANCE = await lpToken.balanceOf(buns) // ensures balance is cleared
        console.log('[buns] LP post-bal: %s', fromWei(POST_BALANCE))

        await expect(POST_BALANCE).to.equal(toWei(93_000))
        
      })

      it('[2W] should withdraw 100% LP', async function() {
        
        await summoner.addPool(500, lpToken.address, true)
        // console.log('added FTM-PAIR: %s', '5x')
        totalPools = await summoner.poolLength()

        expect(await totalPools).to.equal(2)
        // console.log('total pools: %s', totalPools)
        
        await summoner.deposit(1, toWei(HUNDRED_THOUSAND))
        console.log('[buns] deposited: %s FTM-PAIR', HUNDRED_THOUSAND)

        await increaseTime(TWO_WEEKS) // ff 14 days
        await lpToken.burn(toWei(HUNDRED_THOUSAND)) // clears out LP balance from buns
        
        PRE_BALANCE = await lpToken.balanceOf(buns) // ensures balance is cleared
        console.log('[buns] LP pre-bal: %s', fromWei(PRE_BALANCE))
        
        await summoner.withdraw(1, toWei(HUNDRED_THOUSAND))
        POST_BALANCE = await lpToken.balanceOf(buns) // ensures balance is cleared
        console.log('[buns] LP post-bal: %s', fromWei(POST_BALANCE))

        await expect(POST_BALANCE).to.equal(toWei(HUNDRED_THOUSAND))
        
      })
    })

    describe('review: startRate', function() {
      it('should show startRate of 14%, then 7%', async function() {
        START_RATE = await summoner.startRate()
        console.log('startRate: %s%', fromWei(START_RATE))
        await expect(START_RATE).to.equal(toWei(14))

        await summoner.updateStartRate(7)
        
        NEW_START_RATE = await summoner.startRate()
        console.log('newStartRate: %s%', fromWei(NEW_START_RATE))
        await expect(NEW_START_RATE).to.equal(toWei(7))
      })

      it('should show fee of 7% withdrawn after update', async function() {
        await summoner.addPool(500, lpToken.address, true)
        // console.log('added FTM-PAIR: %s', '5x')
        totalPools = await summoner.poolLength()

        expect(await totalPools).to.equal(2)
        // console.log('total pools: %s', totalPools)
        
        await summoner.deposit(1, toWei(HUNDRED_THOUSAND))
        console.log('[buns] deposited: %s FTM-PAIR', HUNDRED_THOUSAND)

        await increaseTime(ONE_DAY) // ff 1 day
        
        START_RATE = await summoner.startRate()
        console.log('startRate: %s%', fromWei(START_RATE))
        await expect(START_RATE).to.equal(toWei(14))

        await summoner.updateStartRate(7)
        NEW_START_RATE = await summoner.startRate()

        console.log('newStartRate: %s%', fromWei(NEW_START_RATE))
        await expect(NEW_START_RATE).to.equal(toWei(7))

        PRE_BALANCE = await lpToken.balanceOf(buns)
        console.log('[buns] pre-balance: %s SOUL', fromWei(PRE_BALANCE))

        PENDING_REWARDS = await summoner.pendingSoul(1, buns)
        console.log('[buns] pending rewards: %s SOUL', fromWei(PENDING_REWARDS))

        await summoner.withdraw(1, toWei(HUNDRED_THOUSAND))
        console.log('[buns] withdrew: %s SOUL', fromWei(HUNDRED_THOUSAND))

        POST_BALANCE = await lpToken.balanceOf(buns)
        console.log('[buns] post-balance: %s SOUL', fromWei(POST_BALANCE))

      })
    })
  })
})

