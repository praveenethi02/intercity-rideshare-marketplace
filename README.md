# Intercity Rideshare, Dynamic Seat-Auction and Cargo Delivery Marketplace

A peer-to-peer intercity ridesharing platform. Drivers sell empty seats through real-time competitive bidding, passengers get affordable long-distance transport along major routes, and cargo delivery extends the same trips.

## Goals

- Reduce intercity travel costs for passengers.
- Create new income for drivers.
- Improve route utilization across the transport network.

## Key features

| Feature | What it does |
| --- | --- |
| Mobile app | Drivers publish seats and routes; passengers bid and track journeys in real time |
| Dynamic seat auction | Real-time bidding on seats, with a bidding ledger and fare settlement |
| Cargo delivery | Customers request delivery, compare driver offers and track the item |
| GPS live tracking | Real-time journey tracking for safety and transparency |
| Push notifications | Bid status, journey progress and important alerts |
| Verification | Checks driver licences, vehicle registration and identity documents before access |
| SMS/OTP authentication | One-time password verification for registration and login |
| Payments | Local payment gateway for fare collection and driver payouts |
| Ratings | Drivers and passengers rate each other after completed trips |
| Admin dashboard | Manages verification, monitors bidding and handles disputes |
| Analytics and reporting | Route utilization, revenue and demand trends |

## Technology

| Area | Technology |
| --- | --- |
| Web frontend | React.js |
| Mobile | Flutter |
| Backend and API | Node.js, Express.js |
| Primary database | PostgreSQL |
| Events and logs | MongoDB |
| Route analysis | Neo4j |
| Cache and live state | Redis |
| Real-time communication | Socket.IO |
| Authentication | JWT, OTP over SMS |
| Maps and GPS | Google Maps Platform or an approved service |
| File storage | Cloudinary or AWS S3 |
| Testing | Jest, Supertest, Playwright, Postman |
| Tooling | Git, GitHub, Docker, GitHub Actions, Swagger/OpenAPI, Jira, Figma |

## Delivery plan

The project is planned as six four-week sprints. Jira holds the live schedule, so individual tasks may move between sprints.

| Sprint | Theme | Outcome |
| --- | --- | --- |
| 1 | Foundation and user access | A user can register, log in and reach permitted areas securely |
| 2 | Driver and vehicle onboarding | Approved drivers and vehicles can be managed |
| 3 | Trips, routes, search and booking | A driver can publish a trip and a passenger can find and book a seat |
| 4 | Seat auction and passenger journey | A passenger can bid, win, confirm a booking and receive journey updates |
| 5 | Cargo marketplace and tracking | A cargo customer can request delivery, select an offer and track it |
| 6 | Payments, operations and release | An integrated release candidate with a final demo |

## Team

| Name | Role |
| --- | --- |
| Praveen Ethipola | Project Manager and Full-Stack Developer |
| Supasan Pramuditha | Full-Stack Developer |
| Teshan Kaluarachchi | Full-Stack Developer |
| Dulanjana Yatagama | Full-Stack Developer |

## Status

In development. Work in progress is on feature branches.

## Repository layout

| Folder | Contents |
| --- | --- |
| [`backend/`](backend/README.md) | Node.js and Express REST API with PostgreSQL |

The mobile app (`mobile/`), web and admin app (`web/`) and project documents (`docs/`) will be added here as they are developed.

## Branches

- `main`: released code.
- `development`: integration branch, where merged work is tested.
- `feature/SCRUM-<number>-<short-name>`: one branch per feature, created from `development`.

## Workflow

1. Update `development` and create a feature branch from it:

   ```bash
   git checkout development
   git pull
   git checkout -b feature/SCRUM-38-driver-registration
   ```

2. Commit with the Jira key in the message, for example `feat(driver): add driver registration` and `Refs: SCRUM-38`.
3. Push the branch and open a pull request into `development`.
4. Merge after review and passing tests.
