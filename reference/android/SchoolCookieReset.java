package dev.campus.jwimport;

import java.net.URI;
import java.util.*;
import java.util.function.Function;

/** Expire only cookies belonging to the school currently being imported. */
final class SchoolCookieReset {
    private static String institution(String host) {
        host=host.toLowerCase(Locale.ROOT);
        String[] labels=host.split("\\.");
        return host.endsWith(".edu.cn") || host.endsWith(".ac.cn")
            ? String.join(".",Arrays.copyOfRange(labels,Math.max(0,labels.length-3),labels.length)) : host;
    }
    static Map<String,Set<String>> requests(String entry, Collection<String> visited, Function<String,String> cookies) {
        URI base=URI.create(entry);
        if(base.getHost()==null || base.getRawUserInfo()!=null || !Arrays.asList("http","https").contains(base.getScheme()))
            throw new IllegalArgumentException("Invalid school entry");
        String domain=institution(base.getHost());
        Map<String,Set<String>> result=new LinkedHashMap<>();
        Set<String> sources=new LinkedHashSet<>();sources.add(entry);sources.addAll(visited);
        for(String raw:sources) {
            if(sources.size()>64)throw new IllegalArgumentException("Too many school pages");
            URI uri=URI.create(raw);String host=uri.getHost();if(host!=null)host=host.toLowerCase(Locale.ROOT);
            if(host==null || uri.getRawUserInfo()!=null || !Arrays.asList("http","https").contains(uri.getScheme())
                || !(host.equals(domain)||host.endsWith("."+domain)))continue;
            String scope=uri.getScheme()+"://"+uri.getRawAuthority();
            result.computeIfAbsent(scope,k->new LinkedHashSet<>());
            String cookieHeader=cookies.apply(scope+(uri.getRawPath().isEmpty()?"/":uri.getRawPath()));
            if(cookieHeader==null)continue;
            Set<String> paths=new LinkedHashSet<>();paths.add("/");
            String path=uri.getRawPath();
            if(path.contains(";"))path=path.substring(0,path.indexOf(';'));
            for(int at=1;at<path.length();at++)if(path.charAt(at)=='/') {paths.add(path.substring(0,at));paths.add(path.substring(0,at+1));}
            if(!path.isEmpty())paths.add(path);
            for(String pair:cookieHeader.split(";")) {
                String name=pair.split("=",2)[0].trim();
                if(!name.matches("[!#$%&'*+.^_`|~0-9A-Za-z-]+"))continue;
                for(String targetPath:paths)for(String cookieDomain:new LinkedHashSet<>(Arrays.asList("",host,domain))) {
                    String expired=name+"=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path="+targetPath
                        +(cookieDomain.isEmpty()?"":"; Domain="+cookieDomain)+("https".equals(uri.getScheme())?"; Secure":"");
                    result.computeIfAbsent(scope,k->new LinkedHashSet<>()).add(expired);
                }
            }
        }
        if(result.values().stream().mapToInt(Set::size).sum()>2048)throw new IllegalArgumentException("Too many school cookies");
        return result;
    }
}
