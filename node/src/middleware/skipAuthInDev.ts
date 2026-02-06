import { Request, Response, NextFunction } from 'express';
import { db } from '@/services/database';


let cachedDevUser: any = null;

export default function skipAuthInDev() {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (process.env.NODE_ENV !== 'development') {
      return next();
    }

    try {
      
      if (cachedDevUser) {
        req.user = cachedDevUser;
        console.log(`🧪 Dev mode: Authentication bypassed ✅ (cached user ${cachedDevUser.id})`);
        return next();
      }

      
      const { data: existingUsers, error: listError } = await db.users().select('*').limit(1);
      if (listError) throw listError;

      let devUser;
      if (existingUsers && existingUsers.length > 0) {
        devUser = existingUsers[0];
        console.log(`🧠 Found existing user: ${devUser.email} (${devUser.id})`);
      } else {
        console.log('🧩 No user found, creating dev user...');
        const { data: newUser, error: insertError } = await db.users()
          .insert({
            email: 'devuser@example.com',
            username: 'dev_user',
            full_name: 'Developer',
            bio: 'Auto-created dev user',
            password: 'dev-mode',
            is_verified: true,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .select()
          .single();

        if (insertError) throw insertError;
        devUser = newUser;
        console.log(`✅ Dev user created: ${devUser.email} (${devUser.id})`);
      }

      
      cachedDevUser = {
        id: devUser.id,
        email: devUser.email,
        name: devUser.full_name || 'Dev User',
      };

      req.user = cachedDevUser;
      console.log(`🧪 Dev mode: Authentication bypassed ✅ (using valid UUID ${devUser.id})`);
    } catch (err) {
      console.error('⚠️ Dev auth setup failed:', err);
      return res.status(500).json({ success: false, error: 'Failed to ensure dev user exists' });
    }

    next();
  };
}
