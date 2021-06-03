#import "ViewController.h"
#import "Test.h"

typedef NS_ENUM(NSInteger, TestType) {
    TestType_001_01 = 1,
    TestType_002_01 = 2,
    TestType_002_02 = 3,
};

typedef NS_ENUM(NSInteger, TestStep) {
    TestStepNone = 0,
    TestStep001 = 1,
    TestStep002 = 2,
};

@interface ViewController ()
@property (nonatomic, weak) IBOutlet UIButton *runButton;
@property (weak, nonatomic) IBOutlet UILabel *messageLabel;

@property (nonatomic, readwrite) NSInteger threadCount;
@property (nonatomic, readwrite) TestStep testStep;

@property (nonatomic, weak) NSTimer *timer;
@property (nonatomic, strong) NSString *dbPath;
@property (nonatomic, strong) NSString *logDirPath;
@property (nonatomic, strong) NSString *logTag;
@end

static NSString* const DB_FILE = @"/db.sqlite3";
static int test001Count = 1000;
static int test002Count = 1000;

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.testStep = TestStepNone;
	self.timer = nil;
	self.dbPath = nil;
	self.logDirPath = nil;
	self.logTag = nil;

	if ([self appInit] == NO) {
		NSLog(@"cannot initialized database.");
		[self.messageLabel setText:@"!!! has error !!!"];
	} else {
		TestInit([self.dbPath UTF8String], [self.logDirPath UTF8String]);
		[self.messageLabel setText:@"status is good."];
        [self.runButton setTitle:@"run" forState:UIControlStateNormal];
	}
}

- (IBAction)onTouchRunButton:(id)sender {
    printf("run button pressed.\n");

	if (self.dbPath == nil) {
    	[self showMessage:@"dbPath is null."];
		return;
	}

	int n = Sqlite3ThreadSafe();
	NSLog(@"Sqlite3ThreadSafe: %d", n);

	[self.messageLabel setText:@"running test."];
	[self.runButton setEnabled:NO];
	[self.runButton setTitle:@"running" forState:UIControlStateNormal];

	[self runTest001];

	[self startTimer];
}

- (void)runTest001 {
	const int Test001ThreadCount = 5;

    self.testStep = TestStep001;
	{
		NSDictionary *dic = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:TestType_001_01], @"TestType",
			nil
		];
		if (test001Count > 0) {
			for (int i = 0; i < Test001ThreadCount; i++) {
				NSThread *thread = [[NSThread alloc] initWithTarget:self
														   selector:@selector(__runTest:)
															 object:dic
				];
				[thread start];
			}
		}
	}
}

- (void)runTest002 {
    self.testStep = TestStep002;
	{
		NSDictionary *dic = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:TestType_002_01], @"TestType",
			nil
		];
		NSThread *thread = [[NSThread alloc] initWithTarget:self
												   selector:@selector(__runTest:)
													 object:dic
		];
		[thread start];
	}
	{
		NSDictionary *dic = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:TestType_002_02], @"TestType",
			nil
		];
		NSThread *thread = [[NSThread alloc] initWithTarget:self
												   selector:@selector(__runTest:)
													 object:dic
		];
		[thread start];
	}
}

- (void)stopTimer {
	if (self.timer) {
	    [self.timer invalidate];
    	self.timer = nil;
	}
}

- (void)startTimer {
	[self stopTimer];
	self.timer = [NSTimer
		scheduledTimerWithTimeInterval:1.0f
								target:self
							  selector:@selector(checkThread:)
							  userInfo:nil
							   repeats:YES
	];
}

- (BOOL)appInit {
	self.dbPath = nil;
	self.logDirPath = nil;
	self.logTag = nil;

	// document配下にパスを取得
	NSArray *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	if ([documentsPath count] <= 0) {
		NSLog(@"database file open error.");
		return NO;
	}
	NSString *docPath = [documentsPath objectAtIndex:0];

	// DBへのフルパスを生成。
	NSString *dbPath = [docPath stringByAppendingPathComponent:DB_FILE];
	NSLog(@"DBPath : %@", dbPath);

	// DBファイルがDocument配下に存在するか判定
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:dbPath]) {
		NSLog(@"db file already exists.");
	} else {
		// アプリケーション内に内包したDBファイルをコピー(初回のみ)
		NSBundle *bundle = [NSBundle mainBundle];
		NSString *orgPath = [bundle bundlePath];
		// 初期ファイルのパス
		orgPath = [orgPath stringByAppendingPathComponent:DB_FILE];
		if (![fileManager fileExistsAtPath:orgPath]) {
			NSLog(@"not found original db file. [%@]", orgPath);
			return NO;
		}
		// アプリケーション内に内包したDBファイルをDocument配下へコピーする
		if (![fileManager copyItemAtPath:orgPath toPath:dbPath error:nil]) {
			//error
			NSLog(@"db file copy failed. [%@] to [%@]", orgPath, dbPath);
			return NO;
		}
	}

	self.dbPath = dbPath;
	self.logDirPath = [NSString stringWithFormat:@"%@/logs/", docPath];
	{
		NSDate* date_source = [NSDate date];
		NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
		[formatter setDateFormat:@"YYYYMMdd-hhmmss"];
		self.logTag = [formatter stringFromDate:date_source];
	}

	NSLog(@"dbPath: [%@]", self.dbPath);
	NSLog(@"logDirPath: [%@]", self.logDirPath);
	NSLog(@"logTag: [%@]", self.logTag);

	[self removeLogDir];
	[self createLogDir];

	return YES;
}

- (BOOL)removeLogDir {
	if (!self.logDirPath) {
		NSLog(@"removeLogDir: logDirPath is nil.");
		return NO;
	}
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSError *error = nil;
	if (![fileManager
			removeItemAtPath:self.logDirPath
					   error:&error]) {
		NSLog(@"Failed to create directory \"%@\". Error: %@", self.logDirPath, error);
		return NO;
	}
	return YES;
}

- (BOOL)createLogDir {
	if (!self.logDirPath) {
		NSLog(@"createLogDir: logDirPath is nil.");
		return NO;
	}
	NSFileManager *fileManager= [NSFileManager defaultManager];
	NSError *error = nil;
	if (![fileManager
			createDirectoryAtPath:self.logDirPath
	  withIntermediateDirectories:YES
					   attributes:nil
							error:&error]) {
		NSLog(@"Failed to create directory \"%@\". Error: %@", self.logDirPath, error);
		return NO;
	}
	return YES;
}

- (void)__runTest: (NSDictionary<NSString *, NSObject *> *)dic {
	NSNumber *dicTestType = [dic objectForKey:@"TestType"];
	TestType testType = [dicTestType intValue];

	long threadID = 0L;
	{
		NSString *s = [NSString stringWithFormat:@"%@", [NSThread currentThread]];
		sscanf(s.UTF8String, "<NSThread: 0x%*12[0-9a-f]>{number = %ld", &threadID);
	}
	const char *str_dbPath = [self.dbPath UTF8String];
	const char *str_logPath = [self.logDirPath UTF8String];

	NSLog(@"++++:%s: START: threadID(%ld), testType(%d)", __func__, threadID, (int)testType);
	@synchronized(self) {
		self.threadCount += 1;
	}

	switch (testType) {
		case TestType_001_01:
			{
				NSString *tmpLogTag = [NSString stringWithFormat:@"%@Test001_01", self.logTag];
				const char *str_logTag = [tmpLogTag UTF8String];
				Test001_01(str_dbPath, str_logPath, str_logTag, test001Count, threadID);
				break;
			}
		case TestType_002_01:
			{
				NSString *tmpLogTag = [NSString stringWithFormat:@"%@Test002_01", self.logTag];
				const char *str_logTag = [tmpLogTag UTF8String];
				Test002_01(str_dbPath, str_logPath, str_logTag, test002Count, threadID);
				break;
			}
		case TestType_002_02:
			{
				NSString *tmpLogTag = [NSString stringWithFormat:@"%@Test002_02", self.logTag];
				const char *str_logTag = [tmpLogTag UTF8String];
				Test002_02(str_dbPath, str_logPath, str_logTag, test002Count, threadID);
				break;
			}
	 	default:
			NSLog(@"Invalid test type !");
			break;
	}

	NSLog(@"++++:%s: END: threadID(%ld), testType(%d)", __func__, threadID, (int)testType);
	@synchronized(self) {
		self.threadCount -= 1;
	}
}

- (void)checkThread: (NSDictionary<NSString *, NSObject *> *)object {
	bool isFinished = false;
	@synchronized(self) {
		if (self.threadCount == 0) {
			isFinished = true;
		}
		NSLog(@"%s: %d\n", __func__, self.threadCount);
	}
	if (!isFinished) {
		return;
	}

	if (self.testStep == TestStep001) {
		NSLog(@"%s: TestStep001 is finished.\n", __func__);
		[self runTest002];
		return;
	}
	if (self.testStep == TestStep002) {
		NSLog(@"%s: TestStep002 is finished.\n", __func__);
	}

	// テスト終了
	[self stopTimer];
	[self.messageLabel setText:@"status is good."];
	[self.runButton setEnabled:YES];
	[self.runButton setTitle:@"run" forState:UIControlStateNormal];
	self.testStep = TestStepNone;

	NSLog(@"### All thread is finished ###\n");
}

- (void)showMessage: (NSString *)message {
	UIAlertController *alertController = [UIAlertController
		alertControllerWithTitle:@"エラー"
						 message:message preferredStyle:UIAlertControllerStyleAlert
	];
	[alertController
		addAction:[UIAlertAction
			actionWithTitle:@"はい"
					  style:UIAlertActionStyleDefault
					handler:^(UIAlertAction *action) {
			  			// otherボタンが押された時の処理
		 			}
		]
	];
	[self presentViewController:alertController animated:YES completion:nil];
}

@end
