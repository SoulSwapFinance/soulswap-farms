const SoulManifester = artifacts.require('SoulManifester.sol');
const Web3 = require('web3');

// NOTE: AVAX ADDRESSES & NETWORK CONFIGURATIONS
const SOUL_AVAX = '0x6Da1AD717C7577AAB46C19aB6d3d9C31aff32A00'
const SOUL_USDC = '0x922fcADa825Dc669798206A35D2D2B455f9A64E7'
const USDC_AVAX = '0x864384a54ea644852603778c0C200eF2D6F2Ac2f'
const BTC_AVAX = '0x8C162C3Bdd7354b5Cb1A0b18eDBB5725CFE762A3'
const ETH_AVAX = '0x5796Bf89f6C7C47811E4E59Ecd7aCACC8A5B9dEF'
const USDC_DAI = '0xE9807645aDA66F2f3d4f2d2A79223701F3cC0903'

module.exports = async function(deployer) {
//   SELECTION = 'DEV';
  SELECTION = 'TEST';
//   SELECTION = 'PROD';
  console.log('user selected: %s', SELECTION);

  MODE = 
    SELECTION == 'TEST' 
      ? web3 = new Web3('ws://api.avax-test.network/ext/C/rpc')
        : SELECTION == 'PROD' 
            ? web3 = new Web3('https://api.avax.network/ext/bc/C/rpc')
                : web3 = new Web3('ws://localhost:8546')

// web3 = new Web3(MODE);

// [manifester]: deploy
  await deployer.deploy(SoulManifester)
  const manifester = await SoulManifester.deployed()

  // [manifester]: add pool
  await manifester.addPool(
        750, // _allocPoint, 
        SOUL_AVAX, // _lpToken, 
        false, // _withUpdate,
        14 // _feeDays
    )

  await manifester.addPool(
        500, // _allocPoint, 
        SOUL_USDC, // _lpToken, 
        false, // _withUpdate,
        14 // _feeDays
  )

  await manifester.addPool(
        250, // _allocPoint, 
        USDC_AVAX, // _lpToken, 
        false, // _withUpdate,
        14 // _feeDays
  )

  await manifester.addPool(
        250, // _allocPoint, 
        BTC_AVAX, // _lpToken, 
        false, // _withUpdate,
        14 // _feeDays
  )

  await manifester.addPool(
        250, // _allocPoint, 
        ETH_AVAX, // _lpToken, 
        false, // _withUpdate,
        14 // _feeDays
  )
  
  await manifester.addPool(
        100, // _allocPoint, 
        USDC_DAI, // _lpToken, 
        false, // _withUpdate,
        14 // _feeDays
  )
}