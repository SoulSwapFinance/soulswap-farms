const { getAddress } = require('@ethersproject/address');
const { expect } = require('chai');
const { accounts, increaseTime, toWei, fromWei, unlockAccount } = require('./utils/testHelper.js');

describe('SoulSummoner', () => {
  const ethers = hre.ethers;
  const THOTH = '0xdffb0b033b8033405f5fb07b08f48c89fa1b4a3d5d5a475c3e2b8df5fbd4da0d';

  beforeEach(async () => {
    
    // fetch and store contracts 
    SoulPower = await ethers.getContractFactory("MockSoulPower");
    SeanceCircle = await ethers.getContractFactory("MockSeanceCircle");
    Summoner = await ethers.getContractFactory("MockSoulSummoner");
    LPToken = await ethers.getContractFactory("MockToken");
    
    provider =  await ethers.provider;
    signer = await provider.getSigner()
  
    // deploy contracts
    soul = await SoulPower.deploy();
    await soul.deployed();
    
    seance = await SeanceCircle.deploy();
    await seance.deployed();
    
    summoner = await Summoner.deploy();
    await summoner.deployed();
    
    lpToken = await LPToken.deploy();
    await lpToken.deployed();
        
    // initialize and grant roles
    await soul.grantRole(THOTH, summoner.address);
    console.log('%s role granted', "THOTH");
    
    await seance.addOperator(summoner.address);
    console.log('operator added')

    await seance.initialize(soul.address);    
    console.log('initialized: seance')
    
    await summoner.initialize(
      soul.address,    // soul
      seance.address, // seance
      0, 1000,       // total weight, weight
      1000,         // staking allocation
      25, 1).unlockAccount       // startRate, dailyDecay
    
    console.log('initialized: summoner')
    
    buns = await signer.getAddress()
    console.log('my address: %s', buns)

    // approve and mint mock and soul
    await soul.approve(summoner.address, toWei(10000))
    lpToken.approve(summoner.address, toWei(1000000))
    lpToken.mint(toWei(1000000))
    console.log("minted %s tokens", 1000000)

    // enter staking
    await summoner.enterStaking(toWei(1000))
    soulBal = await soul.balanceOf(summoner.address)

  })

    describe('deposits / withdraws', function() {
        it('should return 1000 SOUL in the summoner', async function() {
          console.log('summoner soul bal', fromWei(soulBal))
          expect(await soul.balanceOf(summoner.address)).to.equal(toWei(1000))
        })
    })

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

    describe('withdraw staked soul', function() {
        it('should return soul balance + rewards balance', async function() {
        increaseTime(86400)
        pendingRewards = await summoner.pendingSoul(0, buns)
        console.log('pending soul %s: ', fromWei(pendingRewards))
        expect(await summoner.pendingSoul(0, buns)).to.equal(pendingRewards)
        
        soulBal = await soul.balanceOf(summoner.address)
        console.log('summoner soul %s: ', fromWei(pendingRewards))
        expect(await soul.balanceOf(summoner.address)).to.equal(soulBal)
        
        preUserSoul = await soul.balanceOf(buns)
        console.log('pre-withdrawal balance: %s SOUL', preUserSoul)
        await summoner.leaveStaking(toWei(1000))
        newUserSoul = await soul.balanceOf(buns)
        console.log('left staking, new balance: %s SOUL', fromWei(newUserSoul))
        
        dao = await summoner.dao()
        team = await summoner.team()
        
        // todo (below)
        // console.log('amount sent to DAO: %s SOUL', fromWei(soul.balanceOf(dao.address)))
        // console.log('amount sent to TEAM: %s SOUL', fromWei(soul.balanceOf(team.address)))
        // console.log('amount sent to USER: %s SOUL', fromWei(newUserSoul.minus(preUserSoul)))
      })
    })


});

//       // withdraw soul
//       const soulBal2 = await soul.balanceOf(summoner.address)
//       console.log('summoner soul bal', fromWei(soulBal2))

//         // expect(await soul.balanceOf(summoner.address)).to.equal(toWei(100));
//     })
//   })

