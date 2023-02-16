// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import 'lib/typeface/contracts/interfaces/ITypeface.sol';

library DefifaFontImporter {
  // @notice Gets the Base64 encoded Capsules-500.otf typeface
  /// @return The Base64 encoded font file
  function getSkinnyFontSource() internal view returns (bytes memory) {
    return ITypeface(0xA77b7D93E79f1E6B4f77FaB29d9ef85733A3D44A).sourceOf(Font(300, 'normal')); // Capsules font source
  }

  // @notice Gets the Base64 encoded Capsules-500.otf typeface
  /// @return The Base64 encoded font file
  function getBeefyFontSource() internal view returns (bytes memory) {
    return ITypeface(0xA77b7D93E79f1E6B4f77FaB29d9ef85733A3D44A).sourceOf(Font(700, 'normal')); // Capsules font source
  }
}
