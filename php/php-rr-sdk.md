# PHP-SDK proposal
The dynamic nature of PHP provides a wide range of possibilities how workflows can be defined or dynamically generated.
A large variety of instruments, language performance and ease of use opens a lot of possibilities in a field of high-throughput, easy-to-develop
distributed applications. Since PHP 5.5 we can use [cooperative multitasking](https://nikic.github.io/2012/12/22/Cooperative-multitasking-using-coroutines-in-PHP.html) 
which can perfectly align with the workflow execution model.

> Unit testing part of the library is currently of out of the scope of this proposal.

## Table of Contents
- [Activities](#activities)
    - [Registration](#registration)
    - [Using Annotations](#using-annotations)

    - [Payloads](#payloads)
    - [Process Isolation](#process-isolation)
- [Workflows](#workflows)
    - [Registration](#registration-1)
    - [Using Annotations](#using-annotations-1)
    - [Syntax and Atomic Blocks](#syntax-and-atomic-blocks)
    - [Queries](#queries)
    - [Signals](#signals)
    - [Logging](#logging)
    - [Sessions](#sessions)
    - [Deterministic Time](#deterministic-time)
    - [Side Effects](#side-effects)
    - [Error Handling](#error-handling)
    - [Termination and Cancel Requests](#termination-and-cancel-requests)
- [Examples](#examples)
- [Service RPC](#service-rpc)
- [Implementation](#implementation)
    - [Features](#features)
    - [Milestones](#milestones)
- [Development](#development)

## Activities
Similar to other SDKs, the Activity implementation in PHP won't have any feasible limitations. Is it possible to invoke 
any callable function, object method or anonymous function. The invocation arguments can be hydrated based on provided
payload using [method reflection](https://www.php.net/manual/en/class.reflectionfunctionabstract.php) mechanism provided by php.    

The invocation context and heartbeats could be addressed `ContextInterface` object. The error handling done using classic
PHP exceptions.

```php
function processFile(string $url): string
{
    $result = doSomeWork($url);

    return $result;
}
```

Heartbeat example:

```php
use Temporal\Workflow\ActivityContextInterface;
use Temporal\Workflow\Activity;

// parameter order does not matter
function downloadFile(ActivityContextInterface $ctx, string $url)
{
    $downloader = new FileDownloader();
    $downloader->onProgress(function($progress) use($ctx) {
        $ctx->heartbeat($progress);
    });

    return $downloader->download($url);
}
```

Object `ActivityContextInterface` can be used to access task token and other activity related information. The goal of
activity design is to avoid deviation from classic PHP.

To continue activity outside of the execution:

```php

// parameter order does not matter
function waitForUser(ActivityContextInterface $ctx, string $userID)
{
    $this->sendEmailToUser($userID, $ctx->taskToken());

    return $ctx->donNotCompleteOnReturn();
}
```

### Registration
Activities can be registered in corresponding workers. Since workflows will run in different process there are no need to
mix two abstractions together:

```php
$worker = new Activities();
$worker->register('activity.name', 'functionName');

// for objects
$worker->register('activity.name2', [$object, 'methodName']);

// blocking
$worker->run(new RoadRunner\Worker(...));
```

> It might be beneficial to provide underlying registry abstraction to simplify the coding of workflows. See the
> example below.

### Using Annotations
In a more sophisticated frameworks, some activities can be detected and registered automatically using static analysis
of codebase and annotations. No common interface required.

```php
class FileController 
{
    /**
     * @Workflow\Activity("name" = "file.download") 
     */         
    public function processFile(string $file): string 
    {
        $result = $this->doProcessing($file);

        return $result;
    }

    // ...
}
```

> PHP 8 annotations or alternative registration methods possible as well.

### Payloads
The payloads and responses can be serialized and de-serialized to the target format using simple type reflection. 
Such an approach makes possible to use PHP objects as data carrying medium:

```php
class MyObj 
{
    public string $something;
}

function doSomething(ActivityContextInterface $ctx, MyObj $input): Response
{
  // ...
    return new Response('something');
}
```

It is mandatory to use proper type declarations on input and return types of activity. While PHP 7.4 is not widely adopted,
it is recommended to use strict property typing for payload properties as well when possible or highlight the type via
mapper specific annotation.

### Process Isolation
Activity handler will stay in memory permanently, only the execution context will change. Such an approach will ellimitate 
the framework initialization overhead and reduce memory consumption. 

The system must limit to only one concurrent execution per worker, which makes possible to use all existing PHP SPL and vendor
libraries without changes. 

## Workflows
Unlike activities, the workflow execution represented as a physical memory object. In order to ensure proper density
and effectiveness of the system, multiple workflows will locate inside singe PHP process. Each workflow will operate
as one or multiple [Generators](https://www.php.net/manual/en/class.generator.php). The execution can be controlled using
system [keyword](https://www.php.net/manual/en/language.generators.syntax.php) `yield` on blocking operations.

Yield keyword should be used to request the command execution by Temporal system. For the sake of simplify each command
must be presented as typed object, though, end user API can encapsulate object construction using helper functions. 

Each yield command will return Promise/Future object which can later be referenced in a code. Simple workflow execution might
look as following:

```php
use Temporal\Workflow;

class UploadWorkflow
{
    public function run(string $input): string
    {
        $promise = Workflow::executeActivity(
            'activityName',
            $input, 
            Object::class,     // return type, keep null for scalar values
            [
                ExecuteActivy::SCHEDULE_TO_START => 100,        
                ExecuteActivy::START_TO_CLOSE    => 10
            ]       
        );        
    
        // blocking operation to get the activity result
        $result = yield $promise;

        return $result;
    }
}
```

> Activity Stub and builder is currently out of the scope, in first version of library parameters must be passed
> explicitly. All following examples _assume_ existence some form of domain specific activity builder which wraps command
> construction. 

### Context
In order to ensure easy and reliable access to workflow context (including library implementations) we introduce static
methods via `Workflow` class. Since only one workflow can be executed at one moment of time we can safely change the
context before passing control to the workflow:

```php
Workflow::now();
Workflow::isReplying();

// implicit (mapped to context in coordinator) - hidden in implementation
$promise = new Workflow\ExecuteActivy(
    'activityName',
    $input, 
    Object::class,     // return type, keep null for scalar values
    [
        ExecuteActivy::SCHEDULE_TO_START => 100,        
        ExecuteActivy::START_TO_CLOSE    => 10
    ]       
); 

// explicit (similar to above)
$promise = Workflow::executeActivity(
    'activityName',
    $input, 
    Object::class,     // return type, keep null for scalar values
    [
        ExecuteActivy::SCHEDULE_TO_START => 100,        
        ExecuteActivy::START_TO_CLOSE    => 10
    ]   
);
```

> Every `yield` operation called withing in-explicitly set context.

### Registration
Similar to activities each workflow type must be registered within worker context, since worklow might expose more that 
one method (query, primary method) meta declation is required. 

```php
$worker = new WorkflowWorker();

$workflow = (new WorkflowDeclaration('name'))
                ->setClass(WofkflowClass::class)
                ->setHandlerMethod('run')
                ->addQueryHandler('name', 'method-name')
                ->addSignalHandler('name', 'method-name');

$worker->addWorkflow($workflow);
```

> Is it only possible to set one query and signal handler per channel per workflow.

### Using Annotations
In more advanced frameworks it should be possible to register workflows using annotations or attributes.

```php
use Temporal\Workflow\Annotation as Temporal;

/**
 * @Temporal\Workflow(name="name", handler="run")
 */
class Workflow 
{
    public function run(ContextInterface $ctx, string $input): string
    {
        // ...   
    }

    /**
     * @Workflow\QueryMethod(name="something")
     */
    public function querySomething(string $world): string 
    {
        // ...
    }
    
    /**
     * @Workflow\SignalMethod(name="someSignal")
     */
    public function handleSignal(string $input): string 
    {
        // ...
    }
}
``` 

> The actual annotation format is TBD as it irrelevant to the implementation and might vary from framework to framework. 

### Syntax and Atomic Blocks
The building blocks of workflow is `yield` commands which might return actual value or a promise for this value. Every
command wrapped via dedicated class:

```php
function run()
{
    $activity = Workflow::executeActivity('name', 'values', Activity::RETURNS_STRING, [/* options */]);
    
    $result = yield $activity;
}
```

To wait for multiple activities at the same time we can introduce higher level promises such as:

```php
$a = Workflow::executeActivity('a', 'values', A::class, [/* options */]);
$b = Workflow::executeActivity('b', 'values', B::class, [/* options */]);

yield Workflow::waitAll($a, $b);

// or 
yield Workflow::waitAny($a, $b);
```

> More atomic blocks can be added down the road.

#### Timers
Workflow timers can operate as promise or blocking operation:

```php
$timer = Workflow::newTimer(1 * Timer::DAY);
```

Can be combined with Promises:

```php
$a = Workflow::executeActivity(...);
$t = Workflow::newTimer(1 * Time::MINUTE);

yield Workflow::waitAny($a, $t);

if ($t->isReady()) {
    // ...
}
```

> `$this->activitie` simply mocks activity object creation for simplicity of this proposal. 

### Queries
Workflow queries can be easily implemented using dedicated query method of workflow. The state of the workflow can be 
extracted from the properties of the object.

```php
use Temporal\Workflow;

class DemoWorkflow extends Workflow\Workflow
{
    private $step = 0;

    public function queryStep(): int 
    {
        return $this->step;
    }

    public function run(string $input): string
    {
        yield $this->activities->doSomething($input);
        $this->step++;

        // ...
    }
}
```

> Query methods must be registered explicitly.

An alternative approach can be based on registering the callback function during the workflow execution:

```php
Workflow::addQueryHandler('something', function() use (&$step) {
    return $step;
});
```

> Such an approach is more suitable for dynamic workflows. The principle of work is identical to pre-registered queries.

#### Using Annotations
For more advanced frameworks it should be possible to register query method using annotation or attribute (PHP8) as 
in Java SDK.

```php
/**
 * @Workflow\QueryMethod(name="something")
 */
public function querySomething(string $world): string 
{
    return 'hello';
}
```

### Signals
Unlike queries the signals are fist-class citizen of actual workflow code. Unlike activities the signal can be triggered
at any moment, without prior expectation by workflow. 

Signal method can be defined explicitly:

```php
class UploadWorkflow extends Workflow\Workflow
{
    /** @Temporal\SignalMethod(name="signal") */
    public function handleSignal($input):void
    {
    
    }

    public function run(string $input): string
    {
        
    }
}
```

Or at runtime:

```php
public function run(string $input): string
{
    Workflow::addSignalHandler('name', function($input){
    
    });       

    // ...
}
```

#### Handle Signals
Incoming signals can be handled during any workflow `yield` call. Workflow should allow to explicitly wait for signal:

```php
public function run(string $input): string
{
    Workflow::addSignalHandler('name', function($input){
        // do something
    });       

    yield new WaitSignal('name');
}
```

### Logging
The workflow logging does not differ from any other parts of the application, the only exception is the need to exclude
logs triggered while workflow is replaying. We propose to use mocked PSR-3 logger for this purposes:

```php
// TDB
$logger = $worker->setOpions([
    'logger' => new Monolog\Logger(),
    'loggerContext' => function(WorkflowContextInterface $cxt): array { // overwrite
        return [
            'workflowID' => $ctx->getID()
        ];
    } 
]);
```

// Workflow specific non replaying logger

```php
Workflow::getLogger()->debug(...);
```

### Sessions
Sessions can be created as sub-activity group, using similar approach as `withTimeout` and other methods. However,
the explicit yield required. 

```php
public function run(string $input): string
{
    $session = Workflow::newSession([
        Session::CREATION  => 100,
        Session::EXECUTION => 300,
        Session::HEARTBEAT => 30,
        // ... 
    ]);
    
    $a1 = $session->executeActivity($session->executeActivity('activity1', ...));
    $a2 = $session->executeActivity($session->executeActivity('activity2', ...));
    
    $result1 = yield $a1;
    $result2 = yield $a2; 

    // required    
    yield $session->close();
    
    return $result;
}
```

> Session API is subject of change. Current version if base draft only. 

### Cancellable Scopes
Is it possible to define parts of the workflow in a form of cancellable scope:

```php
public function run(string $input): string
{
    $p1 = Workflow::newPromise();
    $cs1 = Workflow::newCancellationScope(function() use ($p1) {
        $p1->from(Workflow::executeActivity('a', ...));
    })->onCancel(function(){
        // logger
    });

    $p2 = Workflow::newPromise();
    $cs2 = Workflow::newCancellationScope(function() use ($p2) {
        $p2->from(Workflow::executeActivity('b', ...));
    })->onCancel(function(){
        // logger
    });
    
    $cs1->run();
    $cs2->run();

    yield Workflow::waitAny($p1, $p2);
    
    $cs1->cancel();
    $cs2->cancel();
}
```

### Deterministic Time
Workflows must avoid calling SPL functions `time()` and `date()`. Context method must be used instead:

```php
Workflow::now(); //DateTimeImmutable object.
```

### Side Effects
Similar to Golang SDK the side effects can be registered using yield call:

```php
$result = Workflow::sideEffect(function(){
    return mt_rand(0, 1000);
});
```

> Similar to other SDKs, PHP version **does not** guarantee that sideEffect won't be called again during the replay. 

### Error Handling
Like in Java version of Temporal SDK the workflow errors can be delivered in form of exceptions triggered on `yield`:

```php
public function run(string $input): string
{
    try {
        return yield $this->activities->doSomething($input);
    } catch (ActivityException $e) {
        // get related activity ID
        $this->logger->warning(
            "Activity %s failed with %s",
            $e->getActivityID(),
            $e->getMessage()
        );       
    }
}
``` 

> The exception tree must follow similar design as Go and Java SDK.

### Termination and Cancel Requests
The cancel requests will be supplied to the workflow in a form of exceptions on `yield` call.
Similar to activity errors workflow can handle these exceptions and perform a proper rollback.

```php
public function run(string $input): string
{
    $step = 0;
    try {
        $resultA = yield $this->activities->doA($input);
        $step++;
        
        $resultB = yield $this->activities->doB($resultA);
        $step++;

        return yield $this->activities->doC($resultB);
    } catch (CancellationException $e) {
        switch ($step) {
            case 2:
                yield $this->activities->rollbackB($resultB);
                // no break
            case 1:
                yield $this->activities->rollbackA($resultA);
        }
    
        throw $e;   
    }
}
```

## Examples
Following examples demonstrates features described above in a more realistic scenarios.

### About Activities Stub
Stable versions of SDK expected to have the default activity building stub to simplify developer life. While it is not
totally clear how this stub will look like (until the API finalized) it can be constructed in workflow `__construct`
method using (no context binding required).

```php
class SubscriptionWorkflow extends Workflow
{
    private ActivitiesInterface $activities;

    public function __construct() 
    {
        $this->activities = Workflow::newActivityStub([/* options */]);    
    }
}
``` 

> The activity stub must be extendable, to allow domain specific building sequences.

### Simple Subscription Workflow
```php
class SubscriptionWorkflow extends Workflow
{
    public function subscriptionWorkflow(string $customerID)
    {
        yield $this->activities->onboardFreeTrial($customerID);
        
        try {
            yield Wofkflow::newTimer(60 * Time::DAY);
            yield $this->activities->upgradeFromTrialToPaid($customerID);
    
            while(true) {
                yield Wofkflow::newTimer(30 * Time::DAY);
                yield $this->activities->chargeMonthlyFee($customerID);
            }       
        }
        catch (CancellationException $e) {
            yield $this->activities->cancelSubscription($customerID);
        }
    }
}
```

### Daily charge using points and then credit card
The workflow provides the ability to accumulate points using signals. You can run one worflow like that per
customer.

```php
class ServiceUsageWorkflow extends Workflow
{
    private int $points = 0;

    /** @Workflow\QueryMethod(name="points") */
    public function getPoints(): int
    {
        return $this->points;
    }

    /** @Workflow\SignalMethod(name="points") */
    public function addPoints(int $points)
    {
        $this->points += $points;
    }

    /** @Workflow(name="serviceUsage") */
    public function run(string $customerID)
    {
        try {
            while(true) {            
                 yield Wofkflow::newTimer(Time::DAY); 
                
                if ($this->points > 0) {
                    $this->points--;
                } else {           
                    yield $this->activities->chargeDailyUsage($customerID);
                    yield $this->activities->prolongAccess($customerID);
                }
            } 
        }
        catch (CancellationException $e) {
            yield $this->activities->cancelAccess($customerID);
            yield $this->activities->cancelSubscription($customerID);
        }
    }
}
```

## Service RPC
The Temporal service SDK in PHP can be written as simple RPC bridge to Golang SDK. This section is pretty straight forward
and does not require much explanation.

```php
use Temporal\Workflow\Service;

// ...

public function doSomething(Service $service)
{
    $service->startWorkflow("workflowName", ["payload"], ...);
}

// ...
```

> Same client can be used to control the state and heartbeats of external activities. 

## Implementation
We propose to implement the SDK as module of [RoadRunner](https://github.com/spiral/roadrunner) application server. The server
written in Golang, tested on production and currently includes all the functions needed to run PHP effectively inside the
Golang application. 
 
### Features
A number of features expected to be implemented in this SDK in order to utilize the scripting nature of PHP efficiently.

#### Performance
One of the side effects of the RoadRunner execution model is the ability to keep PHP process in memory
indefinitely. Unlike classic PHP-FPM applications which recreate the process for each request it guarantees low overhead
and near maximum language [performance](https://www.techempower.com/benchmarks/#section=data-r0&hw=ph&test=fortune&l=zg24n3-f&c=4&a=2&o=e).

#### Plug In Play
Since all the Temporal communication encapsulated in application server the workflow coordination happens over plain
binary protocol between RR and PHP worker. Essentially, it completely eliminates the need to install any PHP extension, 
making integration non-invasive and more reliable.   

> Such an approach makes possible to implement workers in other languages as well (Python, JS) using same SDK.

#### Hot Reload
Due to the scripting nature of PHP it becomes possible to reload the workflow or activity code without stopping the worker (though, 
new SDK API required for workflows). Such an approach makes possible to perform hot deployment of workflow updates, debug
system on production and other things which are nearly impossible in compiled languages.  

### Milestones
A number of steps required to implement such SDK properly:
- receive stable API for Temporal Workflows on Golang (https://github.com/temporalio/temporal-go-sdk/commit/09ced59198a7e5a402ba463a8d11f2952c34dd5e)
- modernize RoadRunner to expose low level async API to communicate with PHP workers

After these steps complete, the implementation can start. 

## Development
The author of this proposal and his team ready to handle the implementation of this SDK for general purpose frameworks 
via RoadRunner module.
