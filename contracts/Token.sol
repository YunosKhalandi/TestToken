// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
  // ------------------------------------------ //
  // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
  // ------------------------------------------ //
  using SafeMath for uint256;
  uint256 public totalSupply;
  uint256 public decimals = 18;
  string public name = "Test token";
  string public symbol = "TEST";
  mapping (address => uint256) public balanceOf;
  // ------------------------------------------ //
  // ----- END: DO NOT EDIT THIS SECTION ------ //  
  // ------------------------------------------ //

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  mapping (address => mapping (address => uint256)) private _allowances;
  uint256 private _numTokenHolders;
  address private _firstTokenHolder;
  address private _lastTokenHolder;
  mapping (address => bool) private _isTokenHolder;
  mapping (address => address) private _nextTokenHolder;
  mapping (address => address) private _prevTokenHolder;
  mapping (address => uint256) private _withdrawableDividends;

  // IERC20

  function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function transfer(address to, uint256 value) external override returns (bool) {
    _transfer(msg.sender, to, value);
    return true;
  }

  function approve(address spender, uint256 value) external override returns (bool) {
    _allowances[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  function transferFrom(address from, address to, uint256 value) external override returns (bool) {
    uint256 allowed = _allowances[from][msg.sender];
    _allowances[from][msg.sender] = allowed.sub(value);
    emit Approval(from, msg.sender, _allowances[from][msg.sender]);
    _transfer(from, to, value);
    return true;
  }

  // IMintableToken

  function mint() external payable override {
    require(msg.value > 0);

    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalSupply = totalSupply.add(msg.value);
    _syncTokenHolder(msg.sender);

    emit Transfer(address(0), msg.sender, msg.value);
  }

  function burn(address payable dest) external override {
    uint256 value = balanceOf[msg.sender];

    balanceOf[msg.sender] = 0;
    totalSupply = totalSupply.sub(value);
    _syncTokenHolder(msg.sender);

    emit Transfer(msg.sender, address(0), value);
    _sendEth(dest, value);
  }

  // IDividends

  function getNumTokenHolders() external view override returns (uint256) {
    return _numTokenHolders;
  }

  function getTokenHolder(uint256 index) external view override returns (address) {
    if (index == 0 || index > _numTokenHolders) {
      return address(0);
    }

    address holder = _firstTokenHolder;

    for (uint256 i = 1; i < index; i++) {
      holder = _nextTokenHolder[holder];
    }

    return holder;
  }

  function recordDividend() external payable override {
    if (msg.value == 0 || totalSupply == 0) {
      revert();
    }

    uint256 remaining = msg.value;
    uint256 numHolders = _numTokenHolders;
    address holder = _firstTokenHolder;

    for (uint256 i = 1; i <= numHolders; i++) {
      address nextHolder = _nextTokenHolder[holder];
      uint256 share = i == numHolders
        ? remaining
        : msg.value.mul(balanceOf[holder]).div(totalSupply);

      _withdrawableDividends[holder] = _withdrawableDividends[holder].add(share);
      remaining = remaining.sub(share);
      holder = nextHolder;
    }
  }

  function getWithdrawableDividend(address payee) external view override returns (uint256) {
    if (payee == address(0)) {
      revert();
    }

    return _withdrawableDividends[payee];
  }

  function withdrawDividend(address payable dest) external override {
    if (dest == address(0)) {
      revert();
    }

    uint256 value = _withdrawableDividends[msg.sender];
    _withdrawableDividends[msg.sender] = 0;
    _sendEth(dest, value);
  }

  function _transfer(address from, address to, uint256 value) private {
    require(to != address(0));

    balanceOf[from] = balanceOf[from].sub(value);
    balanceOf[to] = balanceOf[to].add(value);

    _syncTokenHolder(from);
    _syncTokenHolder(to);

    emit Transfer(from, to, value);
  }

  function _syncTokenHolder(address holder) private {
    if (balanceOf[holder] > 0) {
      if (!_isTokenHolder[holder]) {
        _addTokenHolder(holder);
      }
      return;
    }

    if (_isTokenHolder[holder]) {
      _removeTokenHolder(holder);
    }
  }

  function _addTokenHolder(address holder) private {
    _isTokenHolder[holder] = true;
    _numTokenHolders = _numTokenHolders.add(1);

    if (_lastTokenHolder == address(0)) {
      _firstTokenHolder = holder;
      _lastTokenHolder = holder;
      return;
    }

    _nextTokenHolder[_lastTokenHolder] = holder;
    _prevTokenHolder[holder] = _lastTokenHolder;
    _lastTokenHolder = holder;
  }

  function _removeTokenHolder(address holder) private {
    address prevHolder = _prevTokenHolder[holder];
    address nextHolder = _nextTokenHolder[holder];

    if (prevHolder == address(0)) {
      _firstTokenHolder = nextHolder;
    } else {
      _nextTokenHolder[prevHolder] = nextHolder;
    }

    if (nextHolder == address(0)) {
      _lastTokenHolder = prevHolder;
    } else {
      _prevTokenHolder[nextHolder] = prevHolder;
    }

    delete _prevTokenHolder[holder];
    delete _nextTokenHolder[holder];
    _isTokenHolder[holder] = false;
    _numTokenHolders = _numTokenHolders.sub(1);
  }

  function _sendEth(address payable dest, uint256 value) private {
    if (value == 0) {
      return;
    }

    (bool ok, ) = dest.call{ value: value }("");
    require(ok);
  }
}
