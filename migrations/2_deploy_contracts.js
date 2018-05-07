var WorldCupCardsMarket = artifacts.require("./contracts/WorldCupCardsMarket.sol");

module.exports = function(deployer) {
  deployer.deploy(WorldCupCardsMarket);
};
