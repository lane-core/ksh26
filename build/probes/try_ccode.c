/* probe: ast-ccode — character encoding detection (compile+link+run, capture output) */
#include <stdio.h>
int main(void)
{
	printf("\n");
	printf("#define CC_ASCII\t1\t\t/* ISO-8859-1\t\t\t*/\n");
	printf("#define CC_EBCDIC_E\t2\t\t/* X/Open dd(1) EBCDIC\t\t*/\n");
	printf("#define CC_EBCDIC_I\t3\t\t/* X/Open dd(1) IBM\t\t*/\n");
	printf("#define CC_EBCDIC_O\t4\t\t/* IBM-1047 MVS OpenEdition\t*/\n");
	printf("#define CC_EBCDIC_S\t5\t\t/* Siemens POSIX-bc\t\t*/\n");
	printf("#define CC_EBCDIC_H\t6\t\t/* IBM-37 AS/400\t\t*/\n");
	printf("#define CC_EBCDIC_M\t7\t\t/* IBM MVS COBOL\t\t*/\n");
	printf("#define CC_EBCDIC_U\t8\t\t/* Micro Focus COBOL\t\t*/\n");
	printf("\n");
	printf("#define CC_MAPS\t\t8\t\t/* number of code maps\t\t*/\n");
	printf("\n");
	printf("#define CC_EBCDIC\tCC_EBCDIC_E\n");
	printf("#define CC_EBCDIC1\tCC_EBCDIC_E\n");
	printf("#define CC_EBCDIC2\tCC_EBCDIC_I\n");
	printf("#define CC_EBCDIC3\tCC_EBCDIC_O\n");
	printf("\n");
	switch ('~')
	{
	case 0137:
		printf("#define CC_NATIVE\tCC_EBCDIC_E\t/* native character code\t*/\n");
		break;
	case 0176:
		printf("#define CC_NATIVE\tCC_ASCII\t/* native character code\t*/\n");
		break;
	case 0241:
		switch ('\n')
		{
		case 0025:
			printf("#define CC_NATIVE\tCC_EBCDIC_O\t/* native character code\t*/\n");
			break;
		default:
			switch ('[')
			{
			case 0272:
				printf("#define CC_NATIVE\tCC_EBCDIC_H\t/* native character code\t*/\n");
				break;
			default:
				printf("#define CC_NATIVE\tCC_EBCDIC_I\t/* native character code\t*/\n");
				break;
			}
			break;
		}
		break;
	case 0377:
		printf("#define CC_NATIVE\tCC_EBCDIC_S\t/* native character code\t*/\n");
		break;
	default:
		switch ('A')
		{
		case 0301:
			printf("#define CC_NATIVE\tCC_EBCDIC_O\t/* native character code\t*/\n");
			break;
		default:
			printf("#define CC_NATIVE\tCC_ASCII\t/* native character code\t*/\n");
			break;
		}
		break;
	}
	if ('A' == 0101)
	{
		printf("#define CC_ALIEN\tCC_EBCDIC\t/* alien character code\t\t*/\n\n");
		printf("#define CC_bel\t\t0007\t\t/* bel character\t\t*/\n");
		printf("#define CC_esc\t\t0033\t\t/* esc character\t\t*/\n");
		printf("#define CC_sub\t\t0032\t\t/* sub character\t\t*/\n");
		printf("#define CC_vt\t\t0013\t\t/* vt character\t\t\t*/\n");
	}
	else
	{
		printf("#define CC_ALIEN\tCC_ASCII\t/* alien character code\t\t*/\n\n");
		printf("#define CC_bel\t\t0057\t\t/* bel character\t\t*/\n");
		printf("#define CC_esc\t\t0047\t\t/* esc character\t\t*/\n");
		printf("#define CC_sub\t\t0077\t\t/* sub character\t\t*/\n");
		printf("#define CC_vt\t\t0013\t\t/* vt character\t\t\t*/\n");
	}
	return 0;
}
