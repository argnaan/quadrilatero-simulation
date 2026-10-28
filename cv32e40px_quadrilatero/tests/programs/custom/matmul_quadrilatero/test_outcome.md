| In format | Out format | M  | N  | K  | Test outcome |
|-----------|------------|----|----|----|--------------|
| int32     | int32      | 16 | 8  | 8  | PASSED       |
| int32     | int32      | 16 | 16 | 16 | PASSED       |
| int32     | int32      | 16 | 32 | 32 | PASSED       |
| int32     | int32      | 16 | 64 | 16 | PASSED       |
| int32     | int32      | 16 | 64 | 64 | PASSED       |
| int32     | int32      | 32 | 8  |  8 | PASSED       |
| int32     | int32      | 32 | 16 | 16 | PASSED       |
| int32     | int32      | 32 | 32 | 32 | FAILED       |
| int32     | int32      | 32 | 32 | 64 | FAILED       |
|-----------|------------|----|----|----|--------------|
| int8      | int32      | 8  | 8  | 8  | PASSED       |
| int8      | int32      | 16 | 16 | 16 | PASSED       |
| int8      | int32      | 32 | 32 | 32 | PASSED       |

