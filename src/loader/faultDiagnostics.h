#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <span>

namespace Loader::FaultDiagnostics {

// A guest stack can end inside the requested dump. Keep the readable prefix instead of
// dropping the entire report when a later word crosses a guard page or the stack end.
template <typename Readable>
size_t CaptureStackWords(uint64_t address, std::span<uint64_t> words, Readable&& readable) {
	if (address == 0) return 0;
	size_t count = 0;
	for (auto& word: words) {
		if (address > std::numeric_limits<uint64_t>::max() - sizeof(word) ||
		    !readable(address, sizeof(word))) break;
		std::memcpy(&word, reinterpret_cast<const void*>(address), sizeof(word));
		++count;
		address += sizeof(word);
	}
	return count;
}

} // namespace Loader::FaultDiagnostics
