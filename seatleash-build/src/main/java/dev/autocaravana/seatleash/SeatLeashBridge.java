package dev.autocaravana.seatleash;
import com.mojang.brigadier.CommandDispatcher;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.commands.Commands;
import net.minecraft.commands.arguments.EntityArgument;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.Vec3;
import net.neoforged.fml.common.Mod;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.event.RegisterCommandsEvent;
import net.neoforged.neoforge.event.entity.player.PlayerInteractEvent;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Mod(SeatLeashBridge.ID)
public final class SeatLeashBridge {
    static final String ID="seatleash_bridge";
    static final String TAG="seatleash_permitido";
    static final Map<UUID,UUID> TARGETS=new ConcurrentHashMap<>();
    static final String SEAT="com.simibubi.create.content.contraptions.actors.seat.SeatBlock";
    static final String MOVING="com.simibubi.create.content.contraptions.AbstractContraptionEntity";
    public SeatLeashBridge(){
        NeoForge.EVENT_BUS.addListener(SeatLeashBridge::commands);
        NeoForge.EVENT_BUS.addListener(SeatLeashBridge::block);
        NeoForge.EVENT_BUS.addListener(SeatLeashBridge::entity);
    }
    static void tell(ServerPlayer p,String s){p.sendSystemMessage(Component.literal("[SeatLeash] "+s));}
    static void commands(RegisterCommandsEvent ev){
        CommandDispatcher<CommandSourceStack> d=ev.getDispatcher();
        d.register(Commands.literal("seatleash")
        .then(Commands.literal("objetivo").then(Commands.argument("jugador",EntityArgument.player()).executes(c->{
            ServerPlayer p=c.getSource().getPlayerOrException(), q=EntityArgument.getPlayer(c,"jugador");
            TARGETS.put(p.getUUID(),q.getUUID()); tell(p,"Objetivo: "+q.getGameProfile().getName()); return 1;
        })))
        .then(Commands.literal("limpiar").executes(c->{ServerPlayer p=c.getSource().getPlayerOrException();TARGETS.remove(p.getUUID());tell(p,"Objetivo borrado.");return 1;}))
        .then(Commands.literal("sentar").executes(c->{
            ServerPlayer p=c.getSource().getPlayerOrException();
            if(!p.getMainHandItem().is(Items.LEAD)){tell(p,"Sujeta una rienda.");return 0;}
            ServerPlayer t=target(p);if(!allowed(p,t))return 0;
            boolean ok=mountMoving(p,t);tell(p,ok?"Jugador sentado.":"No se encontro asiento libre de Create en la direccion apuntada.");return ok?1:0;
        }))
        .then(Commands.literal("permitir").requires(s->s.hasPermission(2)).then(Commands.argument("jugador",EntityArgument.player()).executes(c->{
            ServerPlayer t=EntityArgument.getPlayer(c,"jugador");t.addTag(TAG);c.getSource().sendSuccess(()->Component.literal("Permitido: "+t.getGameProfile().getName()),true);return 1;
        })))
        .then(Commands.literal("prohibir").requires(s->s.hasPermission(2)).then(Commands.argument("jugador",EntityArgument.player()).executes(c->{
            ServerPlayer t=EntityArgument.getPlayer(c,"jugador");t.removeTag(TAG);c.getSource().sendSuccess(()->Component.literal("Prohibido: "+t.getGameProfile().getName()),true);return 1;
        }))));
    }
    static ServerPlayer target(ServerPlayer p){
        UUID id=TARGETS.get(p.getUUID());
        if(id!=null)return p.getServer().getPlayerList().getPlayer(id);
        return p.serverLevel().getPlayers(q->q!=p&&q.distanceToSqr(p)<64).stream().min(Comparator.comparingDouble(p::distanceToSqr)).orElse(null);
    }
    static boolean allowed(ServerPlayer p,ServerPlayer t){
        if(t==null||t==p||t.level()!=p.level()||t.distanceToSqr(p)>64){tell(p,"Jugador no encontrado o demasiado lejos.");return false;}
        if(!p.hasPermissions(2)&&!t.getTags().contains(TAG)){tell(p,"Sin permiso: /seatleash permitir <jugador>");return false;}
        if(t.isPassenger()){tell(p,"El objetivo ya esta sentado.");return false;}
        return true;
    }
    static Class<?> cls(String name){try{return Class.forName(name);}catch(Throwable t){return null;}}
    static void block(PlayerInteractEvent.RightClickBlock ev){
        if(ev.getLevel().isClientSide()||!(ev.getEntity() instanceof ServerPlayer p)||ev.getHand()!=InteractionHand.MAIN_HAND||!p.isShiftKeyDown()||!ev.getItemStack().is(Items.LEAD))return;
        Class<?> seat=cls(SEAT);if(seat==null||!seat.isInstance(ev.getLevel().getBlockState(ev.getPos()).getBlock()))return;
        ServerPlayer t=target(p);if(!allowed(p,t))return;
        if(sitBlock(ev.getLevel(),ev.getPos(),t)){ev.setCanceled(true);ev.setCancellationResult(InteractionResult.SUCCESS);tell(p,"Sentado.");}
        else tell(p,"No se pudo usar el asiento. En naves Sable puede necesitar integracion adicional.");
    }
    static boolean sitBlock(Level level,BlockPos pos,ServerPlayer target){
        try{
            Class<?> seat=cls(SEAT);
            Object occupied=seat.getMethod("isSeatOccupied",Level.class,BlockPos.class).invoke(null,level,pos);
            if(Boolean.TRUE.equals(occupied))return false;
            seat.getMethod("sitDown",Level.class,BlockPos.class,Entity.class).invoke(null,level,pos,target);
            return target.isPassenger();
        }catch(Throwable t){System.err.println("[SeatLeash] SeatBlock: "+t);return false;}
    }
    static void entity(PlayerInteractEvent.EntityInteract ev){
        if(ev.getLevel().isClientSide()||!(ev.getEntity() instanceof ServerPlayer p)||ev.getHand()!=InteractionHand.MAIN_HAND||!p.isShiftKeyDown()||!p.getMainHandItem().is(Items.LEAD))return;
        if(!moving(ev.getTarget()))return;
        ServerPlayer t=target(p);if(!allowed(p,t))return;
        if(tryMount(ev.getTarget(),p,t)){ev.setCanceled(true);ev.setCancellationResult(InteractionResult.SUCCESS);tell(p,"Sentado en contraption.");}
    }
    static boolean moving(Entity e){Class<?> c=cls(MOVING);return c!=null&&c.isInstance(e);}
    record SeatChoice(Entity entity,int index,double score){}
    static SeatChoice choice(Entity e,ServerPlayer p){
        try{
            Object c=e.getClass().getMethod("getContraption").invoke(e);if(c==null)return null;
            @SuppressWarnings("unchecked") List<BlockPos> seats=(List<BlockPos>)c.getClass().getMethod("getSeats").invoke(c);
            @SuppressWarnings("unchecked") Map<UUID,Integer> used=(Map<UUID,Integer>)c.getClass().getMethod("getSeatMapping").invoke(c);
            Method glob=e.getClass().getMethod("toGlobalVector",Vec3.class,float.class);
            Vec3 eye=p.getEyePosition(), view=p.getLookAngle();SeatChoice best=null;
            for(int i=0;i<seats.size();i++){
                if(used.containsValue(i))continue;BlockPos bp=seats.get(i);
                Vec3 pos=(Vec3)glob.invoke(e,new Vec3(bp.getX()+0.5,bp.getY()+0.5,bp.getZ()+0.5),1f);
                Vec3 diff=pos.subtract(eye);double len=diff.lengthSqr(),forward=diff.dot(view);
                if(len>64||len<0.01||forward<0)continue;
                double miss=len-forward*forward;if(miss>1.44)continue;
                double score=miss*4+len/64;
                if(best==null||score<best.score())best=new SeatChoice(e,i,score);
            }
            return best;
        }catch(Throwable t){System.err.println("[SeatLeash] Contraption seat scan: "+t);return null;}
    }
    static boolean mount(Entity e,int i,ServerPlayer t){
        try{e.getClass().getMethod("addSittingPassenger",Entity.class,int.class).invoke(e,t,i);return t.isPassenger();}
        catch(Throwable x){System.err.println("[SeatLeash] Passenger mount: "+x);return false;}
    }
    static boolean tryMount(Entity e,ServerPlayer p,ServerPlayer t){SeatChoice s=choice(e,p);return s!=null&&mount(e,s.index(),t);}
    static boolean mountMoving(ServerPlayer p,ServerPlayer t){
        List<Entity> entities=p.serverLevel().getEntitiesOfClass(Entity.class,p.getBoundingBox().inflate(8),SeatLeashBridge::moving);
        return entities.stream().map(e->choice(e,p)).filter(Objects::nonNull).sorted(Comparator.comparingDouble(SeatChoice::score)).anyMatch(s->mount(s.entity(),s.index(),t));
    }
}
