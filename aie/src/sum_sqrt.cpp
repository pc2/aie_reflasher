#include "kernels.h"
#include <adf.h>
#include <aie_api/aie.hpp>

// z = sqrt(x^2 + y^2). Built with -DDOUBLE_OUTPUT (make aie-b -> libadf_b.a) the result is
// multiplied by 2, so a reflash from graph A to graph B is visible as doubled outputs.

void sum_sqrt_kernel(adf::input_buffer<float, adf::extents<WINDOW_SIZE>> &in_x, adf::input_buffer<float, adf::extents<WINDOW_SIZE>> &in_y,
		adf::output_buffer<float, adf::extents<WINDOW_SIZE>> &out) {
	auto inXIt = aie::cbegin_vector<VECTOR_SIZE>(in_x);
	auto inYIt = aie::cbegin_vector<VECTOR_SIZE>(in_y);
	auto outIt = aie::begin_vector<VECTOR_SIZE>(out);

	for (int i = 0; i < WINDOW_SIZE / VECTOR_SIZE; ++i) {
		auto inX_i = *inXIt++;
		auto inY_i =*inYIt++;
#ifdef DOUBLE_OUTPUT
		*outIt++ = aie::mul(aie::sqrt(aie::add(inX_i, inY_i)), aie::broadcast<float, VECTOR_SIZE>(2.0f));
#else
		*outIt++ = aie::sqrt(aie::add(inX_i, inY_i));
#endif
	}
}
