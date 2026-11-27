#include "loader/faultDiagnostics.h"

#include <array>
#include <cstdio>
#include <cstdlib>
#include <limits>

static void Check(bool condition, const char* message) {
	if (!condition) {
		std::fprintf(stderr, "FAILED: %s\n", message);
		std::exit(1);
	}
}

int main() {
	using Loader::FaultDiagnostics::CaptureStackWords;
	std::array<uint64_t, 19> source {};
	for (size_t i = 0; i < source.size(); ++i) source[i] = 0x900000000ull + i;
	const auto begin = reinterpret_cast<uint64_t>(source.data());
	const auto end = begin + sizeof(source);
	auto readable = [begin, end](uint64_t address, uint64_t size) {
		return address >= begin && address <= end && size <= end - address;
	};
	std::array<uint64_t, 32> output;
	output.fill(0xfeedface);
	auto count = CaptureStackWords(begin, output, readable);
	Check(count == 19, "readable prefix is retained at the guest stack boundary");
	for (size_t i = 0; i < count; ++i) Check(output[i] == source[i], "captured word differs");
	Check(output[19] == 0xfeedface, "unreadable suffix must not be touched");
	Check(CaptureStackWords(end - 8, output, readable) == 1, "last complete stack word");
	Check(CaptureStackWords(end - 4, output, readable) == 0, "partial word must not be read");
	Check(CaptureStackWords(end, output, readable) == 0, "stack end is not readable");
	Check(CaptureStackWords(begin, std::span<uint64_t>(output).first(3), readable) == 3,
	      "respect output capacity");
	bool probed = false;
	auto reject = [&probed](uint64_t, uint64_t) { probed = true; return false; };
	Check(CaptureStackWords(0, output, reject) == 0 && !probed, "null stack rejected");
	Check(CaptureStackWords(std::numeric_limits<uint64_t>::max() - 3, output, reject) == 0 &&
	          !probed, "wrapping range rejected before probing");
	std::puts("Fault diagnostics: all stack-boundary checks passed.");
}
