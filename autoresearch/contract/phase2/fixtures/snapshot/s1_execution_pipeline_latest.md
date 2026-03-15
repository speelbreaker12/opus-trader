## **1\. Execution Architecture: The "Atomic Group" (Real-Time Repair)**
Profile: CSP

**Constraint**: We do not rely on API atomicity. We rely on **Runtime Atomicity**. If Leg A fills and Leg B dies, the system detects the "Mixed State" and neutralizes it immediately, without waiting for a restart.
