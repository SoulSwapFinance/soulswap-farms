const { getAddress } = require('@ethersproject/address');
const { expect } = require('chai');
const { address, increaseTime, toWei, fromWei } = require('./utils/testHelper.js');

describe('SoulSummoner', () => {
    const ethers = hre.ethers;
    const THOTH = '0xdffb0b033b8033405f5fb07b08f48c89fa1b4a3d5d5a475c3e2b8df5fbd4da0d';

  beforeEach(async () => {

    // fetch and store contracts 
    SoulPower = await ethers.getContractFactory("MockSoulPower");
    SeanceCircle = await ethers.getContractFactory("MockSeanceCircle");
    Summoner = await ethers.getContractFactory("MockSoulSummoner");
    LPToken = await ethers.getContractFactory("MockERC20");

    // deploy contracts
    summoner = await Summoner.deploy();
    await summoner.deployed();

    // LPToken = await ethers.getContractFactory('MockToken');
    // lpToken = await LPToken.deploy();
    // await lpToken.deployed();
    
    // deploy contracts
    soul = await SoulPower.deploy();
    await soul.deployed();
    
    seance = await SeanceCircle.deploy();
    await seance.deployed();
    
    summoner = await Summoner.deploy();
    await summoner.deployed();
    
    // initialize and grant roles
    await soul.grantRole(THOTH, summoner.address);
    console.log('role successfully granted');
    
    await seance.addOperator(summoner.address);
    await seance.initialize(soul.address);    
    
    await summoner.initialize(
      soul.address,    // soul
      seance.address, // seance
      0, 1000,       // total weight, weight
      1000,         // staking allocation
      25, 1)       // startRate, dailyDecay
      
    // approve and mint mock and soul
    // const soulApprovalTx = 
    await soul.approve(summoner.address, toWei(1000))
    // await soulApprovalTx

    // mockToken.approve(summoner.address, toWei(1000000))
    // mockToken.mint(toWei(1000000))

  })

    describe('deposits / withdraws', function() {
        it('should return new balances', async function() {
          // stake soul
          summoner.enterStaking(toWei(100))
          soulBal = await soul.balanceOf(summoner.address)
          // await checkSoulBalanceTx
          console.log('summoner soul bal', fromWei(soulBal));

          increaseTime(43200);
          expect(await soul.balanceOf(summoner.address)).to.equal(toWei(100));
        })
    })

    // describe('view rewards days one and two', function() {
    //     it('should return new rewards', async function() {
    //       increaseTime(43200)
    //     expect(await soul.balanceOf(summoner.address)).to.equal(100);
    //     })
    // })

});



      
//       // view pending rewards
      
//       // increase time and view pending rewards after 24H
//       await increaseTime(86400)
//       // const deployer = await

//       const pendingStakingRewards = await summoner.pendingSoul(0, this.address)
//       await pendingStakingRewards

//       // withdraw soul
//       const soulBal2 = await soul.balanceOf(summoner.address)
//       console.log('summoner soul bal', fromWei(soulBal2))

//         // expect(await soul.balanceOf(summoner.address)).to.equal(toWei(100));
//     })
//   })

