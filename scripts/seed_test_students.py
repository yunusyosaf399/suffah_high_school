"""Synthetic admissions only. Dry run by default; uses Application Default Credentials."""
import argparse
from datetime import datetime, timezone, date
from collections import Counter

CLASSES = ["nursery-a", "kg-a"] + ["grade-1-a", "grade-2"] + [f"grade-{i}-a" for i in range(3,10)]

def plan(count):
    if not 1 <= count <= 100:
        raise ValueError("Count must be between 1 and 100")
    return [(i, CLASSES[(i-1)%len(CLASSES)]) for i in range(1,count+1)]

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--project",required=True)
    p.add_argument("--count",type=int,default=100)
    p.add_argument("--apply",action="store_true")
    p.add_argument("--confirm",default="")
    args=p.parse_args()
    rows=plan(args.count)
    if args.apply and args.confirm != args.project:
        p.error("Apply requires exact target project ID as confirmation")
    import firebase_admin
    from firebase_admin import firestore
    firebase_admin.initialize_app(options={"projectId":args.project})
    db=firestore.client()
    today=datetime.now(timezone.utc).date()
    year=today.year
    reg=db.document(f"counters/student_registration_{year}")
    roll=db.document("counters/student_roll_global")
    ts=firestore.SERVER_TIMESTAMP
    labels={}
    for c in sorted(set(c for _,c in rows)):
        snap=db.document(f"classes/{c}").get()
        d=snap.to_dict() or {}
        if d.get("active") is not True:
            raise RuntimeError(f"Missing or inactive class: {c}")
        labels[c]=d["name"]+(" – "+d["section"] if d.get("section") else "")
    print("Project:",args.project,"Mode:", "APPLY" if args.apply else "DRY RUN")
    print("Allocation:",dict(Counter(c for _,c in rows)))
    print("Registration counter:", (reg.get().to_dict() or {}).get("last",0))
    print("Roll counter:", (roll.get().to_dict() or {}).get("last",9999))
    pending=[]
    for n,c in rows:
        if not db.document(f"system_migrations/test_seed_100_v1_{n:03d}").get().exists:
            pending.append((n,c))
    print("Pending students:",len(pending),"Already seeded:",len(rows)-len(pending))
    if not args.apply:
        print("Dry run: zero writes")
        return

    @firestore.transactional
    def seed(tx,n,c):
        marker=db.document(f"system_migrations/test_seed_100_v1_{n:03d}")
        if marker.get(transaction=tx).exists:
            return False
        cls=db.document(f"classes/{c}").get(transaction=tx).to_dict() or {}
        if cls.get("active") is not True:
            raise RuntimeError("Class no longer active")
        rr=reg.get(transaction=tx).to_dict() or {}
        ro=roll.get(transaction=tx).to_dict() or {}
        seq=int(rr.get("last",0))+1
        rn=int(ro.get("last",9999))+1
        sid=f"ST-{year}-{seq:04d}"
        student=db.document(f"students/{sid}")
        if student.get(transaction=tx).exists:
            raise RuntimeError("Registration collision; check counters")
        name=f"TEST Student {n:03d}"
        guardian=f"TEST Guardian {n:03d}"
        gender="Male" if n%2 else "Female"
        age=4+CLASSES.index(c)
        dob=date(year-age, (n%12)+1, (n%27)+1).isoformat()
        day=today.isoformat()
        details={
            "student":dict(firstName="TEST",middleName="Student",lastName=f"{n:03d}",gender=gender,dateOfBirth=dob,idNumber="",idType="National ID",nationality="Pakistan"),
            "guardian":dict(firstName="TEST",middleName="Guardian",lastName=f"{n:03d}",relationship="Father",email=f"guardian{n:03d}@example.invalid",phone="",whatsapp="",emergencyPhone="",occupation="",idNumber=""),
            "contact":dict(city="",country="Pakistan",email="",emergencyPhone="",neighborhood="",phone="",postalCode="",street="",whatsapp=""),
            "academic":dict(academicYear=f"{year}–{year+1}",admissionDate=day,campus="Main",classId=c,previousGrade="",previousSchool="",term="Annual",transcriptNotes="Synthetic test record"),
            "health":dict(allergies="",bloodGroup="",medicalConditions="",specialNeeds="")
        }
        base=dict(active=True,classId=c,fullName=name,rollNo=str(rn))
        tx.create(student,dict(base,admissionNo=sid,admittedAt=ts,attachments={},createdAt=ts,currentStep=6,details=details,gender=gender,guardianName=guardian,guardianPhone="",parentUids=[],photoPath="",searchName=name.lower(),status="admitted",updatedAt=ts))
        directory=dict(base,studentId=sid,updatedAt=ts)
        tx.create(db.document(f"class_rosters/{c}/students/{sid}"),directory)
        tx.create(db.document(f"inventory_student_directory/{sid}"),directory)
        tx.create(db.document(f"parent_profiles/{sid}"),dict(base,admissionDate=day,admissionNo=sid,dateOfBirth=dob,gender=gender,nationality="Pakistan",status="admitted"))
        tx.create(db.document(f"parent_children/{sid}"),dict(classId=c,className=labels[c],fullName=name,historyClassIds=[c]))
        tx.create(db.document(f"parent_documents/{sid}"),dict(attachments={},photoPath=""))
        tx.set(reg,dict(last=seq,updatedAt=ts),merge=True)
        tx.set(roll,dict(last=rn,updatedAt=ts),merge=True)
        tx.create(marker,dict(studentId=sid,seed="test_seed_100_v1",createdAt=ts))
        return True
    created=sum(seed(db.transaction(),n,c) for n,c in pending)
    print("Created:",created,"Previously seeded:",len(rows)-len(pending))

if __name__=="__main__":
    main()
