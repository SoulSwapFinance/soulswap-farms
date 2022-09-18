const { expect } = require('chai')
const { increaseTime, toWei } = require('./utils/testHelper.js')

describe('SoulPower', () => {
  const ethers = hre.ethers
  const ONE_DAY = 86_400
  const THOTH = '0xdffb0b033b8033405f5fb07b08f48c89fa1b4a3d5d5a475c3e2b8df5fbd4da0d'

  beforeEach(async () => {
    
    // fetch and store contracts 
    SoulPower = await ethers.getContractFactory('MockSoulPowerAny')    
    provider =  await ethers.provider;
    signer = await provider.getSigner()
  
    buns = await signer.getAddress()
    console.log('my address: %s', buns)

    // deploy contracts
    soul = await SoulPower.deploy()
    await soul.deployed()

    // burn totalSupply
    totalSupply = await soul.totalSupply()
    await soul.burn(buns, totalSupply)

  })

    // deposit test
    describe('test mint and burn', function() {

      it('should mint 1K SOUL', async function() {
        await soul.mint(buns, toWei(1_000))
        expect(await soul.totalSupply()).to.equal(toWei(1_000))
        })

      it('should burn 500 SOUL', async function() {
        await soul.mint(buns, toWei(1_000))
        await soul.burn(buns, toWei(500))
        expectation = toWei(500)
        expect(await soul.totalSupply()).to.equal(expectation)
        })
    })
})