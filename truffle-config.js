require('babel-register');
require('babel-polyfill');
require('dotenv').config();
const HDWalletProvider = require('truffle-hdwallet-provider-privkey');
const privateKeys = process.env.PK || ""

module.exports = {
  networks: {
      development: {
        host: "127.0.0.1",
        port: 7545,
        network_id: "*"
      },
      testnet: {
        provider: function() {
          return new HDWalletProvider(
            privateKeys.split(','), // Array of account private keys
            )
            `https://api.avax-test.network/ext/C/rpc`// URL to Blockchain Node
        },
        gas: 5000000,
        gasPrice: 25000000000,
        network_id: 43113
      },
      avalanche: {
        provider: function() {
          return new HDWalletProvider(
            privateKeys.split(','), // Array of account private keys
            )
            `https://api.avax.network/ext/bc/C/rpc`// URL to Blockchain Node
        },
        gas: 5000000,
        gasPrice: 25000000000,
        network_id: 43114
      }
    },
    plugins: [
      'truffle-plugin-verify',
      'truffle-contract-size'
    ],
    api_keys: {
      etherscan: process.env.ETHERSCAN_API_KEY
    },
    compilers: {
      solc: {
        version: "^0.8.17"
      }
    },
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      }
    }
};
