# Schedules

- [Docs](https://docs.temporal.io/workflows/#schedules)
- gRPC API:
  - [methods](https://github.com/temporalio/api/blob/799926c86eb13d8a9717d3561ab9b0df43796c06/temporal/api/workflowservice/v1/service.proto#L328-L370)
  - [`request_response.proto`](https://github.com/temporalio/api/blob/799926c86eb13d8a9717d3561ab9b0df43796c06/temporal/api/workflowservice/v1/request_response.proto#L821-L957)
  - [`schedule/v1/message.proto`](https://github.com/temporalio/api/blob/master/temporal/api/schedule/v1/message.proto)
  - [`ScheduleOverlapPolicy` enum](https://github.com/temporalio/api/blob/master/temporal/api/enums/v1/schedule.proto)

## TS API

```ts
import { ScheduleClient, ScheduleOverlapPolicy } from '@temporalio/client'
import { addWeeks } from 'date-fns'
import { myWorkflow } from './workflows'

const client = new ScheduleClient()

const schedule = await client.create({
  id: 'biz-id',
  spec: {
    // every hour at minute 5
    interval: {
      every: '1h',
      at: '5m',
    },
    // every 20 days since epoch at day 2
    // interval: {
    //   every: '20d',
    //   at: '2d'
    // }
    exclude: {
      // skip 11:05 pm
      hour: 23,
      minute: 5,
    },
    endAt: addWeeks(new Date(), 4), 
    jitter: '30s',
    timezone: 'US/Eastern',
  },
  action: {
    startWorkflow: {
      workflowId: 'biz-id',
      type: myWorkflow,
      args: ['sorry this is the only thing reused, chad 😄'],
    },
  },
  policies: {
    overlap: ScheduleOverlapPolicy.BUFFER_ONE,
    catchupWindow: '2m',
    pauseOnFailure: true,
  },
  state: {
    note: 'started schedule',
    paused: true,
    limitedActions: 10,
  },
  patch: {
    triggerImmediately: true,
    backfill: [
      {
        start: new Date(),
        end: new Date(),
        overlap: ScheduleOverlapPolicy.ALLOW_ALL,
      },
    ],
    pause: true, // redundant with state.paused above (can use either)
  },
  memo,
  searchAttributes,
})

const scheduleDescription = await schedule.describe()

const matchingStartTimes = await schedule.listMatchingTimes({ start: new Date(), end: new Date() })

await schedule.update({
  spec,
  action,
  policies,
  state,
  conflictToken: scheduleDescription.conflictToken,
})

await schedule.patch({
  triggerImmediately: true,
  backfill,
  unpause: true,
})

await schedule.delete()

const { schedules, nextPageToken } = await client.list({
  pageSize: 50,
  nextPageToken: 'base64',
})
```

### Higher-level client

```ts
import { Client } from '@temporalio/client'

const client = new Client()

client.schedule.create()
client.workflow.start() 
client.asyncCompletion.heartbeat()
client.operator.addSearchAttributes()
```