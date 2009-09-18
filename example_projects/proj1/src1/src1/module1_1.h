#ifndef MODULE_1_1_H
#define MODULE_1_1_H

#include "src2/module2_1.h"

class module1_1
{
	public:

		int h() {return 3;}
		module2_1* ptr() {return new module2_1;}
};

#endif
