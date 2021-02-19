/*

https://icecreamswap.finance/

Telegram: https://t.me/IceCreamSwap

Twitter: https://twitter.com/SwapIceCream

*/

pragma solidity 0.6.12;

import "./libs/token/BEP20/BEP20.sol";

contract CreamShare is BEP20('CreamShare', 'ICS') {
    constructor( uint256 _amount ) public {
        _mint(msg.sender, _amount);
        renounceOwnership();
    }
}