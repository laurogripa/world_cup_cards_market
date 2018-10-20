pragma solidity ^0.4.24;

contract WorldCupCardsMarket {

  address owner;

  string public name = "WORLD_CUP_2018_CARDS";
  uint256 public nextCardId = 1;
  uint32 public totalSupply = 100000000; // 100 millions of each type;
  uint16 private maxCardTypes = 681; // 682 types of cards
  uint16 private specCardMagicNumber = 1000;
  uint8 private specCardsLimit = 5;
  uint256 public packPriceInWei = 1000000000000000; // 0.001 ETH
  uint8 public cardPerPack = 5;

  struct Card {
    uint256 id;
    uint256 cardType;
    bool special;
    uint64 birthTime;
  }

  struct Offer {
    bool isForSale;
    Card card;
    address seller;
    uint minValue;          // in ether
    address onlySellTo;     // specify to sell only to a specific person
  }

  struct Bid {
    bool hasBid;
    Card card;
    address bidder;
    uint value;
  }

  // Address => (CardId => Card);
  mapping (address => mapping (uint => Card)) public cards;
  // Address => Balance;
  mapping (address => uint256) public balanceOf;
  // CardId => Offer;
  mapping (uint => Offer) public cardsOfferedForSale;
  // CardId => Bid;
  mapping (uint => Bid) public cardBids;
  // Address => pending value;
  mapping (address => uint) public pendingWithdrawals;

  event Assign(address indexed to, uint indexed cardId);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event CardTransfer(address indexed from, address indexed to, uint indexed cardId);
  event CardOffered(uint indexed cardId, uint minValue, address indexed toAddress);
  event CardBidEntered(uint indexed cardId, uint value, address indexed fromAddress);
  event CardBidWithdrawn(uint indexed cardId, uint value, address indexed fromAddress);
  event CardBought(uint indexed cardId, uint value, address indexed fromAddress, address indexed toAddress);
  event CardNoLongerForSale(uint indexed cardId);

  /* Initializes contract with initial supply tokens to the creator of the contract */
  function WorldCupCards() public {
    owner = msg.sender;
  }

  // Transfer ownership of a card to another user without requiring payment
  function transferCard(address to, uint cardId) public {
    Card memory card = cards[msg.sender][cardId];
    require(card.id != 0x0);

    if (cardsOfferedForSale[cardId].isForSale) {
      cardNoLongerForSale(cardId);
    }

    cards[to][cardId] = card;
    delete cards[msg.sender][cardId];
    balanceOf[msg.sender]--;
    balanceOf[to]++;
    emit Transfer(msg.sender, to, 1);
    emit CardTransfer(msg.sender, to, cardId);
    // Check for the case where there is a bid from the new owner and refund it.
    // Any other bid can stay in place.
    Bid memory bid = cardBids[cardId];
    if (bid.bidder == to) {
      // Kill bid and refund value
      pendingWithdrawals[to] += bid.value;
      cardBids[cardId] = Bid(false, card, to, 0);
    }
  }

  function cardNoLongerForSale(uint cardId) public {
    Card memory card = cards[msg.sender][cardId];
    require(card.id != 0x0);
    cardsOfferedForSale[cardId] = Offer(false, card, msg.sender, 0, 0x0);
    emit CardNoLongerForSale(cardId);
  }

  function offerCardForSale(uint cardId, uint minSalePriceInWei) public {
    Card memory card = cards[msg.sender][cardId];
    require(card.id != 0x0);
    cardsOfferedForSale[cardId] = Offer(true, card, msg.sender, minSalePriceInWei, 0x0);
    emit CardOffered(cardId, minSalePriceInWei, 0x0);
  }

  function offerCardForSaleToAddress(uint cardId, uint minSalePriceInWei, address toAddress) public {
    Card memory card = cards[msg.sender][cardId];
    require(card.id != 0x0);
    cardsOfferedForSale[cardId] = Offer(true, card, msg.sender, minSalePriceInWei, toAddress);
    emit CardOffered(cardId, minSalePriceInWei, toAddress);
  }

  function buyCard(uint cardId) payable public {
    Offer memory offer = cardsOfferedForSale[cardId];
    address seller = offer.seller;
    Card memory card = cards[seller][cardId];
    require(offer.isForSale);
    require(offer.onlySellTo == 0x0 || offer.onlySellTo == msg.sender);
    require(msg.value >= offer.minValue);
    require(card.id != 0x0);

    cards[msg.sender][cardId] = card;
    delete cards[seller][cardId];

    balanceOf[seller]--;
    balanceOf[msg.sender]++;
    emit Transfer(seller, msg.sender, 1);

    cardNoLongerForSale(cardId);
    pendingWithdrawals[seller] += msg.value;
    emit CardBought(cardId, msg.value, seller, msg.sender);

    // Check for the case where there is a bid from the new owner and refund it.
    // Any other bid can stay in place.
    Bid memory bid = cardBids[cardId];
    if (bid.bidder == msg.sender) {
      // Kill bid and refund value
      pendingWithdrawals[msg.sender] += bid.value;
      cardBids[cardId] = Bid(false, card, 0x0, 0);
    }
  }

  function buyCardsPack() payable public {
    require(msg.value >= packPriceInWei);

    uint quantity = (msg.value / packPriceInWei) % 2;
    bool arriveLimit = ((nextCardId + (quantity * cardPerPack)) > (maxCardTypes * totalSupply));
    require(!arriveLimit);

    owner.transfer(msg.value);
    generateAndDeliveryPackedCards(quantity * cardPerPack, msg.sender);
  }

  function generateAndDeliveryPackedCards(uint quantity, address to) internal {
    uint generated = 0;
    while (generated <= quantity) {
      uint256 cardId = nextCardId++;
      uint256 cardType = randomMax(maxCardTypes);
      bool isSpecial = randomMax(specCardMagicNumber) < specCardsLimit;

      Card memory _card = Card({
        id: cardId,
        cardType: cardType,
        special: isSpecial,
        birthTime: uint64(now)
      });

      cards[to][cardId] = _card;
      generated++;
      emit Assign(to, cardId);
    }
  }

  function withdraw() public {
    uint amount = pendingWithdrawals[msg.sender];
    // Remember to zero the pending refund before
    // sending to prevent re-entrancy attacks
    pendingWithdrawals[msg.sender] = 0;
    msg.sender.transfer(amount);
  }

  function enterBidForCard(uint cardId, address cardOwner) payable public {
    Card memory card = cards[cardOwner][cardId];
    Bid memory existing = cardBids[cardId];

    require(card.id != 0x0);
    require(cardOwner != msg.sender);
    require(msg.value > 0);
    require(msg.value >= existing.value);
    if (existing.value > 0) {
        // Refund the failing bid
        pendingWithdrawals[existing.bidder] += existing.value;
    }
    cardBids[cardId] = Bid(true, card, msg.sender, msg.value);
    emit CardBidEntered(cardId, msg.value, msg.sender);
  }

  function acceptBidForCard(uint cardId, uint minPrice) public {
    Card memory card = cards[msg.sender][cardId];
    require(card.id != 0x0);
    address seller = msg.sender;
    Bid memory bid = cardBids[cardId];
    require(bid.value > 0);
    require(bid.value >= minPrice);

    cards[bid.bidder][cardId] = card;
    delete cards[msg.sender][cardId];
    balanceOf[seller]--;
    balanceOf[bid.bidder]++;
    emit Transfer(seller, bid.bidder, 1);

    cardsOfferedForSale[cardId] = Offer(false, card, bid.bidder, 0, 0x0);
    uint amount = bid.value;
    cardBids[cardId] = Bid(false, card, 0x0, 0);
    pendingWithdrawals[seller] += amount;
    emit CardBought(cardId, bid.value, seller, bid.bidder);
  }

  function withdrawBidForCard(uint cardId) public {
    Card memory card = cards[msg.sender][cardId];
    require(card.id != 0x0);
    Bid memory bid = cardBids[cardId];
    require(bid.bidder == msg.sender);

    emit CardBidWithdrawn(cardId, bid.value, msg.sender);
    uint amount = bid.value;
    cardBids[cardId] = Bid(false, card, 0x0, 0);
    // Refund the bid money
    msg.sender.transfer(amount);
  }

  function randomMax(uint max) internal view returns (uint randomNumber) {
    return(uint(keccak256(blockhash(block.number-1), now)) % max);
  }
}
