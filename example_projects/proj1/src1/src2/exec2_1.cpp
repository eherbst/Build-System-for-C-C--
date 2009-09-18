#include "subdir-without-cpps/extutils.h"
#include "src1/module1_2.h"
#include "module2_1.h"

int main()
{
	beUseful();
	module2_1 m21;
	module1_2 m12;
	m12.j();
	m21.m.j();
	return 0;
}
